#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 1.3 deployment - validates Hub infrastructure and connectivity.

.DESCRIPTION
Validates:
- Hub resource group and network resources exist
- VNet DNS servers point to on-prem DNS
- VNet peering is established between Hub and On-Prem
- VMs are running and can resolve internet DNS names
- Package updates work (internet connectivity via NAT Gateway)

.PARAMETER ResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER VnetName
Hub VNet name. Default: hub-vnet

.PARAMETER DnsVmName
Hub DNS VM name. Default: hub-vm-dns

.PARAMETER AppVmName
Hub App VM name. Default: hub-vm-app

.EXAMPLE
./phase1-3-test.ps1

.EXAMPLE
./phase1-3-test.ps1 -ResourceGroupName "my-hub-rg"
#>

param(
    [string]$ResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$VnetName = 'hub-vnet',
    [string]$DnsVmName = 'hub-vm-dns',
    [string]$AppVmName = 'hub-vm-app'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.3 Validation Tests - Hub Infrastructure          ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message
    )

    Write-Host "[TEST] $Name" -ForegroundColor Yellow

    if ($Success) {
        Write-Host '  ✓ PASS' -ForegroundColor Green
        $script:passCount++
    }
    else {
        Write-Host "  ✗ FAIL: $Message" -ForegroundColor Red
        $script:failCount++
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Test 1: Resource Group exists
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Resource Group Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$rgExists = az group exists --name $ResourceGroupName
Test-Result -Name 'Hub resource group exists' -Success ($rgExists -eq 'true') -Message "Resource group $ResourceGroupName not found"

# Test 2: VNet exists and has DNS configured
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Network Resources Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$vnet = az network vnet show --resource-group $ResourceGroupName --name $VnetName 2>$null | ConvertFrom-Json

if ($vnet) {
    Test-Result -Name "Hub VNet exists ($VnetName)" -Success $true -Message ''
    
    # Check DNS servers
    $onpremDnsIp = az vm show -d --resource-group $OnpremResourceGroupName --name 'onprem-vm-dns' --query 'privateIps' -o tsv 2>$null
    
    if ($vnet.dhcpOptions.dnsServers -and ($vnet.dhcpOptions.dnsServers -contains $onpremDnsIp)) {
        Test-Result -Name "VNet DNS points to on-prem DNS ($onpremDnsIp)" -Success $true -Message ''
    }
    else {
        Test-Result -Name 'VNet DNS points to on-prem DNS' -Success $false -Message "Expected DNS: $onpremDnsIp, Got: $($vnet.dhcpOptions.dnsServers -join ', ')"
    }
}
else {
    Test-Result -Name "Hub VNet exists ($VnetName)" -Success $false -Message 'VNet not found'
}

# Test 3: NAT Gateway exists
$natGw = az network nat gateway show --resource-group $ResourceGroupName --name 'hub-natgw' 2>$null | ConvertFrom-Json
Test-Result -Name 'NAT Gateway exists (hub-natgw)' -Success ($null -ne $natGw) -Message 'NAT Gateway not found'

# Test 4: Azure Bastion exists
$bastion = az network bastion show --resource-group $ResourceGroupName --name 'hub-bastion' 2>$null | ConvertFrom-Json
Test-Result -Name 'Azure Bastion exists (hub-bastion)' -Success ($null -ne $bastion) -Message 'Bastion not found'

# Test 5: VNet Peering exists
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet Peering Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$peeringToOnprem = az network vnet peering show --resource-group $ResourceGroupName --vnet-name $VnetName --name 'hub-to-onprem' 2>$null | ConvertFrom-Json

if ($peeringToOnprem) {
    $peeringStatus = $peeringToOnprem.peeringState -eq 'Connected'
    Test-Result -Name 'Peering Hub->OnPrem (hub-to-onprem)' -Success $peeringStatus -Message "Peering state: $($peeringToOnprem.peeringState)"
}
else {
    Test-Result -Name 'Peering Hub->OnPrem (hub-to-onprem)' -Success $false -Message 'Peering not found'
}

$peeringFromOnprem = az network vnet peering show --resource-group $OnpremResourceGroupName --vnet-name 'onprem-vnet' --name 'onprem-to-hub' 2>$null | ConvertFrom-Json

if ($peeringFromOnprem) {
    $peeringStatus = $peeringFromOnprem.peeringState -eq 'Connected'
    Test-Result -Name 'Peering OnPrem->Hub (onprem-to-hub)' -Success $peeringStatus -Message "Peering state: $($peeringFromOnprem.peeringState)"
}
else {
    Test-Result -Name 'Peering OnPrem->Hub (onprem-to-hub)' -Success $false -Message 'Peering not found'
}

# Test 6: VMs exist and are running
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Virtual Machine Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$dnsVm = az vm show -d --resource-group $ResourceGroupName --name $DnsVmName 2>$null | ConvertFrom-Json

if ($dnsVm) {
    $vmRunning = $dnsVm.powerState -eq 'VM running'
    Test-Result -Name "$DnsVmName is running" -Success $vmRunning -Message "Power state: $($dnsVm.powerState)"
}
else {
    Test-Result -Name "$DnsVmName exists" -Success $false -Message 'VM not found'
}

$appVm = az vm show -d --resource-group $ResourceGroupName --name $AppVmName 2>$null | ConvertFrom-Json

if ($appVm) {
    $vmRunning = $appVm.powerState -eq 'VM running'
    Test-Result -Name "$AppVmName is running" -Success $vmRunning -Message "Power state: $($appVm.powerState)"
}
else {
    Test-Result -Name "$AppVmName exists" -Success $false -Message 'VM not found'
}

# Test 7: DNS resolution from Hub VMs
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Resolution Tests' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test DNS resolution on DNS VM
$dnsTestOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts 'nslookup google.com 2>&1 | grep -q "Address:" && echo "RESOLVED" || echo "FAILED"' `
    --query 'value[0].message' -o tsv 2>$null

$dnsResolved = [bool]($dnsTestOutput -match 'RESOLVED')
Test-Result -Name "$DnsVmName can resolve google.com" -Success $dnsResolved -Message "Resolution test output: $dnsTestOutput"

# Test DNS resolution on App VM
$appDnsTestOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $AppVmName `
    --command-id RunShellScript `
    --scripts 'nslookup microsoft.com 2>&1 | grep -q "Address:" && echo "RESOLVED" || echo "FAILED"' `
    --query 'value[0].message' -o tsv 2>$null

$appDnsResolved = [bool]($appDnsTestOutput -match 'RESOLVED')
Test-Result -Name "$AppVmName can resolve microsoft.com" -Success $appDnsResolved -Message "Resolution test output: $appDnsTestOutput"

# Test 8: Package updates work (internet connectivity)
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Internet Connectivity Tests' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$updateTestOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $AppVmName `
    --command-id RunShellScript `
    --scripts 'apt-get update -qq 2>&1 && echo "UPDATE_SUCCESS" || echo "UPDATE_FAILED"' `
    --query 'value[0].message' -o tsv 2>$null

$updateSuccess = [bool]($updateTestOutput -match 'UPDATE_SUCCESS')
Test-Result -Name "$AppVmName can run apt-get update" -Success $updateSuccess -Message "Update test output: $updateTestOutput"

# Summary
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host "Passed: $script:passCount" -ForegroundColor Green
Write-Host "Failed: $script:failCount" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($script:passCount + $script:failCount)" -ForegroundColor White
Write-Host ''

if ($script:failCount -gt 0) {
    Write-Host 'Some tests failed. Please review the output above.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Troubleshooting:' -ForegroundColor Yellow
    Write-Host '  - Verify Phase 1.2 (on-prem DNS) is deployed and operational' -ForegroundColor White
    Write-Host '  - Check VNet peering status in Azure Portal' -ForegroundColor White
    Write-Host '  - Verify DNS VM is running and accessible' -ForegroundColor White
    Write-Host '  - Check NSG rules allow traffic between VNets' -ForegroundColor White
    exit 1
}

Write-Host 'All tests passed! ✓' -ForegroundColor Green
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  - Proceed to Phase 1.4 to configure Hub DNS services' -ForegroundColor White
Write-Host '  - Or connect to VMs via Azure Bastion for manual validation' -ForegroundColor White
