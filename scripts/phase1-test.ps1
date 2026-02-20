#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 1 infrastructure deployment.

.DESCRIPTION
Validates:
- Resource groups exist
- VNets are deployed with correct address spaces
- All VMs are running and accessible
- VMs are using Azure DNS (168.63.129.16)
- VMs have internet connectivity
- No VNet peering exists (that comes in Phase 2)

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.EXAMPLE
./phase1-test.ps1
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubResourceGroupName = 'rg-hub-dnsmig'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1 Validation Tests - Infrastructure                ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ''
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

Write-Host 'Configuration:' -ForegroundColor Cyan
Write-Host "  On-prem RG: $OnpremResourceGroupName" -ForegroundColor White
Write-Host "  Hub RG:     $HubResourceGroupName" -ForegroundColor White
Write-Host ''

# ================================================
# Resource Groups
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Resource Groups' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$onpremRgExists = az group exists --name $OnpremResourceGroupName
Test-Result -Name 'On-prem resource group exists' -Success ($onpremRgExists -eq 'true') -Message "Resource group not found: $OnpremResourceGroupName"

$hubRgExists = az group exists --name $HubResourceGroupName
Test-Result -Name 'Hub resource group exists' -Success ($hubRgExists -eq 'true') -Message "Resource group not found: $HubResourceGroupName"

# ================================================
# VNets
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Virtual Networks' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$onpremVnet = az network vnet show --resource-group $OnpremResourceGroupName --name 'onprem-vnet' 2>$null | ConvertFrom-Json
Test-Result -Name 'On-prem VNet exists' -Success ($null -ne $onpremVnet) -Message 'VNet not found'

if ($onpremVnet) {
    $onpremAddressSpace = $onpremVnet.addressSpace.addressPrefixes -contains '10.0.0.0/16'
    Test-Result -Name 'On-prem VNet address space is 10.0.0.0/16' -Success $onpremAddressSpace -Message 'Unexpected address space'
}

$hubVnet = az network vnet show --resource-group $HubResourceGroupName --name 'hub-vnet' 2>$null | ConvertFrom-Json
Test-Result -Name 'Hub VNet exists' -Success ($null -ne $hubVnet) -Message 'VNet not found'

if ($hubVnet) {
    $hubAddressSpace = $hubVnet.addressSpace.addressPrefixes -contains '10.1.0.0/16'
    Test-Result -Name 'Hub VNet address space is 10.1.0.0/16' -Success $hubAddressSpace -Message 'Unexpected address space'
}

# ================================================
# DNS Configuration (should be Azure DNS)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$onpremDnsServers = $onpremVnet.dhcpOptions.dnsServers
$onpremUsingAzureDns = ($null -eq $onpremDnsServers) -or ($onpremDnsServers.Count -eq 0)
Test-Result -Name 'On-prem VNet using Azure DNS (no custom DNS)' -Success $onpremUsingAzureDns -Message "Custom DNS configured: $($onpremDnsServers -join ', ')"

$hubDnsServers = $hubVnet.dhcpOptions.dnsServers
$hubUsingAzureDns = ($null -eq $hubDnsServers) -or ($hubDnsServers.Count -eq 0)
Test-Result -Name 'Hub VNet using Azure DNS (no custom DNS)' -Success $hubUsingAzureDns -Message "Custom DNS configured: $($hubDnsServers -join ', ')"

# ================================================
# VNet Peering (should not exist)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet Peering' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$onpremPeerings = az network vnet peering list --resource-group $OnpremResourceGroupName --vnet-name 'onprem-vnet' | ConvertFrom-Json
Test-Result -Name 'No peering on on-prem VNet (Phase 2)' -Success ($onpremPeerings.Count -eq 0) -Message "Found $($onpremPeerings.Count) peering(s)"

$hubPeerings = az network vnet peering list --resource-group $HubResourceGroupName --vnet-name 'hub-vnet' | ConvertFrom-Json
Test-Result -Name 'No peering on hub VNet (Phase 2)' -Success ($hubPeerings.Count -eq 0) -Message "Found $($hubPeerings.Count) peering(s)"

# ================================================
# Virtual Machines
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Virtual Machines' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# On-prem DNS VM
$onpremDnsVm = az vm show --resource-group $OnpremResourceGroupName --name 'onprem-vm-dns' --show-details 2>$null | ConvertFrom-Json
Test-Result -Name 'On-prem DNS VM exists' -Success ($null -ne $onpremDnsVm) -Message 'VM not found'

if ($onpremDnsVm) {
    $onpremDnsRunning = $onpremDnsVm.powerState -eq 'VM running'
    Test-Result -Name 'On-prem DNS VM is running' -Success $onpremDnsRunning -Message "Power state: $($onpremDnsVm.powerState)"
    
    $onpremDnsIp = $onpremDnsVm.privateIps
    $onpremDnsIpCorrect = $onpremDnsIp -eq '10.0.10.4'
    Test-Result -Name 'On-prem DNS VM has IP 10.0.10.4' -Success $onpremDnsIpCorrect -Message "Actual IP: $onpremDnsIp"
}

# On-prem Client VM
$onpremClientVm = az vm show --resource-group $OnpremResourceGroupName --name 'onprem-vm-client' --show-details 2>$null | ConvertFrom-Json
Test-Result -Name 'On-prem Client VM exists' -Success ($null -ne $onpremClientVm) -Message 'VM not found'

if ($onpremClientVm) {
    $onpremClientRunning = $onpremClientVm.powerState -eq 'VM running'
    Test-Result -Name 'On-prem Client VM is running' -Success $onpremClientRunning -Message "Power state: $($onpremClientVm.powerState)"
    
    $onpremClientIp = $onpremClientVm.privateIps
    $onpremClientIpCorrect = $onpremClientIp -eq '10.0.10.5'
    Test-Result -Name 'On-prem Client VM has IP 10.0.10.5' -Success $onpremClientIpCorrect -Message "Actual IP: $onpremClientIp"
}

# Hub DNS VM
$hubDnsVm = az vm show --resource-group $HubResourceGroupName --name 'hub-vm-dns' --show-details 2>$null | ConvertFrom-Json
Test-Result -Name 'Hub DNS VM exists' -Success ($null -ne $hubDnsVm) -Message 'VM not found'

if ($hubDnsVm) {
    $hubDnsRunning = $hubDnsVm.powerState -eq 'VM running'
    Test-Result -Name 'Hub DNS VM is running' -Success $hubDnsRunning -Message "Power state: $($hubDnsVm.powerState)"
    
    $hubDnsIp = $hubDnsVm.privateIps
    $hubDnsIpCorrect = $hubDnsIp -eq '10.1.10.4'
    Test-Result -Name 'Hub DNS VM has IP 10.1.10.4' -Success $hubDnsIpCorrect -Message "Actual IP: $hubDnsIp"
}

# Hub App VM
$hubAppVm = az vm show --resource-group $HubResourceGroupName --name 'hub-vm-app' --show-details 2>$null | ConvertFrom-Json
Test-Result -Name 'Hub App VM exists' -Success ($null -ne $hubAppVm) -Message 'VM not found'

if ($hubAppVm) {
    $hubAppRunning = $hubAppVm.powerState -eq 'VM running'
    Test-Result -Name 'Hub App VM is running' -Success $hubAppRunning -Message "Power state: $($hubAppVm.powerState)"
    
    $hubAppIp = $hubAppVm.privateIps
    $hubAppIpCorrect = $hubAppIp -eq '10.1.10.5'
    Test-Result -Name 'Hub App VM has IP 10.1.10.5' -Success $hubAppIpCorrect -Message "Actual IP: $hubAppIp"
}

# ================================================
# Internet Connectivity
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Internet Connectivity' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test on-prem DNS VM internet connectivity (with retry for transient network issues)
$onpremDnsInternetOk = $false
$onpremDnsInternet = ''
for ($i = 1; $i -le 2; $i++) {
    $onpremDnsInternet = az vm run-command invoke `
        --resource-group $OnpremResourceGroupName `
        --name 'onprem-vm-dns' `
        --command-id RunShellScript `
        --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 15 2>&1 || echo "curl_failed"' `
        --query 'value[0].message' -o tsv 2>$null
    
    if ($onpremDnsInternet -match '200') {
        $onpremDnsInternetOk = $true
        break
    }
    
    if ($i -eq 1) {
        Start-Sleep -Seconds 3
    }
}
Test-Result -Name 'On-prem DNS VM can access internet' -Success $onpremDnsInternetOk -Message "HTTP response: $onpremDnsInternet"

# Test hub DNS VM internet connectivity (with retry for transient network issues)
$hubDnsInternetOk = $false
$hubDnsInternet = ''
for ($i = 1; $i -le 2; $i++) {
    $hubDnsInternet = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name 'hub-vm-dns' `
        --command-id RunShellScript `
        --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 15 2>&1 || echo "curl_failed"' `
        --query 'value[0].message' -o tsv 2>$null
    
    if ($hubDnsInternet -match '200') {
        $hubDnsInternetOk = $true
        break
    }
    
    if ($i -eq 1) {
        Start-Sleep -Seconds 3
    }
}
Test-Result -Name 'Hub DNS VM can access internet' -Success $hubDnsInternetOk -Message "HTTP response: $hubDnsInternet"

# ================================================
# Package Management
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Package Management' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test apt-get update on on-prem client VM
$onpremAptUpdate = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'apt-get update > /dev/null 2>&1 && echo "success"' `
    --query 'value[0].message' -o tsv 2>$null

$onpremAptOk = [bool]($onpremAptUpdate -match 'success')
Test-Result -Name 'On-prem Client VM can update package lists' -Success $onpremAptOk -Message 'apt-get update failed'

# Test apt-get update on hub app VM
$hubAptUpdate = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'apt-get update > /dev/null 2>&1 && echo "success"' `
    --query 'value[0].message' -o tsv 2>$null

$hubAptOk = [bool]($hubAptUpdate -match 'success')
Test-Result -Name 'Hub App VM can update package lists' -Success $hubAptOk -Message 'apt-get update failed'

# ================================================
# Azure Bastion
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Azure Bastion' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Use generic resource check - much faster than bastion-specific commands during provisioning
$onpremBastionResource = az resource list --resource-group $OnpremResourceGroupName --resource-type 'Microsoft.Network/bastionHosts' --name 'onprem-bastion' --query '[0].id' -o tsv 2>$null
$onpremBastionExists = ![string]::IsNullOrWhiteSpace($onpremBastionResource)
Test-Result -Name 'On-prem Bastion exists' -Success $onpremBastionExists -Message 'Bastion not found'

$hubBastionResource = az resource list --resource-group $HubResourceGroupName --resource-type 'Microsoft.Network/bastionHosts' --name 'hub-bastion' --query '[0].id' -o tsv 2>$null
$hubBastionExists = ![string]::IsNullOrWhiteSpace($hubBastionResource)
Test-Result -Name 'Hub Bastion exists' -Success $hubBastionExists -Message 'Bastion not found'

# ================================================
# Summary
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host "Passed: $script:passCount" -ForegroundColor Green
Write-Host "Failed: $script:failCount" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($script:passCount + $script:failCount)" -ForegroundColor White
Write-Host ''

if ($script:failCount -gt 0) {
    Write-Host 'Some tests failed. Review the output above for details.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Common issues:' -ForegroundColor Yellow
    Write-Host '  - VMs may still be provisioning (check Azure portal)' -ForegroundColor White
    Write-Host '  - VM extensions may still be running (wait a few minutes)' -ForegroundColor White
    Write-Host '  - Network connectivity may be establishing' -ForegroundColor White
    exit 1
}

Write-Host 'All tests passed! ✓' -ForegroundColor Green
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Establish VNet peering between on-prem and hub:' -ForegroundColor White
Write-Host '     ./scripts/phase2-deploy.ps1' -ForegroundColor Green
Write-Host '  2. After peering, configure DNS services (Phases 3-6)' -ForegroundColor White
Write-Host ''

exit 0
