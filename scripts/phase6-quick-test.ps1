#!/usr/bin/env pwsh
<#
.SYNOPSIS
Quick validation of Phase 6 Hub DNS cutover.

.DESCRIPTION
Performs essential checks only:
- Hub VNet DNS configuration
- Hub VM DNS configuration
- Key resolution tests
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubVnetName = 'hub-vnet',
    [string]$HubDnsServerIp = '10.1.10.4'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 6 Quick Validation                                 ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

$passCount = 0
$failCount = 0

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ''
    )
    
    if ($Success) {
        Write-Host "[✓] $Name" -ForegroundColor Green
        $script:passCount++
    }
    else {
        Write-Host "[✗] $Name" -ForegroundColor Red
        if ($Message) {
            Write-Host "    $Message" -ForegroundColor Yellow
        }
        $script:failCount++
    }
}

# Check Hub VNet DNS
Write-Host 'Checking Hub VNet DNS configuration...' -ForegroundColor Cyan
$vnetDns = az network vnet show `
    --resource-group $HubResourceGroupName `
    --name $HubVnetName `
    --query 'dhcpOptions.dnsServers' -o tsv 2>$null

Test-Result -Name "Hub VNet uses custom DNS ($HubDnsServerIp)" -Success ($vnetDns -eq $HubDnsServerIp)

# Check Hub VMs DNS configuration
Write-Host 'Checking Hub VM DNS configuration...' -ForegroundColor Cyan
$hubAppDns = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "resolvectl status 2>&1 | grep 'DNS Servers' | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$hubAppDnsStr = if ($hubAppDns) { [string]$hubAppDns } else { '' }
Test-Result -Name "Hub App VM using $HubDnsServerIp" -Success ($hubAppDnsStr -match $HubDnsServerIp) -Message "Got: $hubAppDnsStr"

# Test azure.pvt resolution from Hub
Write-Host 'Testing DNS resolution from Hub...' -ForegroundColor Cyan
$azureZoneTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup dns.azure.pvt 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$azureZoneTestStr = if ($azureZoneTest) { [string]$azureZoneTest } else { '' }
Test-Result -Name 'Hub VM resolves dns.azure.pvt' -Success ($azureZoneTestStr -match '10\.1\.10\.4') -Message "Got: $azureZoneTestStr"

# Test onprem.pvt resolution from Hub (bidirectional)
Write-Host 'Testing cross-environment resolution...' -ForegroundColor Cyan
$onpremZoneTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup dns.onprem.pvt 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$onpremZoneTestStr = if ($onpremZoneTest) { [string]$onpremZoneTest } else { '' }
Test-Result -Name 'Hub VM resolves dns.onprem.pvt via forwarding' -Success ($onpremZoneTestStr -match '10\.0\.10\.4') -Message "Got: $onpremZoneTestStr"

# Test azure.pvt resolution from On-prem (opposite direction)
$azureFromOnprem = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup dns.azure.pvt 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$azureFromOnpremStr = if ($azureFromOnprem) { [string]$azureFromOnprem } else { '' }
Test-Result -Name 'On-prem VM resolves dns.azure.pvt via forwarding' -Success ($azureFromOnpremStr -match '10\.1\.10\.4') -Message "Got: $azureFromOnpremStr"

# Test internet resolution
Write-Host 'Testing internet resolution...' -ForegroundColor Cyan
$internetTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup www.microsoft.com 2>&1 | grep -E 'Address: .+\..+\..+\..+'" `
    --query 'value[0].message' -o tsv 2>$null

$internetTestStr = if ($internetTest) { [string]$internetTest } else { '' }
Test-Result -Name 'Hub VM can resolve internet domains' -Success ($internetTestStr -match 'Address:') -Message 'Got internet response'

# Summary
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host "Results: $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ''

if ($failCount -eq 0) {
    Write-Host '✓ Phase 6 validation complete - DNS migration successful!' -ForegroundColor Green
    Write-Host ''
    Write-Host 'All environments now using custom BIND9 DNS with bidirectional forwarding.' -ForegroundColor Cyan
    exit 0
}
else {
    Write-Host '⚠ Some tests failed. Review the output above.' -ForegroundColor Yellow
    exit 1
}
