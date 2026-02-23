#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 6 Hub DNS cutover - final validation.

.DESCRIPTION
Validates:
- Hub VNet DNS settings point to custom DNS server (10.1.10.4)
- Hub VMs have acquired new DNS settings via DHCP
- Hub VMs can resolve azure.pvt records using custom DNS
- Hub VMs can resolve onprem.pvt records via forwarding
- On-prem VMs can resolve azure.pvt records via forwarding
- Internet resolution still works through DNS forwarding
- Full bidirectional DNS resolution across both environments

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubVnetName
Hub VNet name. Default: hub-vnet

.PARAMETER HubDnsZone
Hub DNS zone name. Default: azure.pvt

.PARAMETER OnpremDnsZone
On-prem DNS zone name. Default: onprem.pvt

.PARAMETER HubDnsServerIp
Hub DNS server IP address. Default: 10.1.10.4

.EXAMPLE
./phase6-test.ps1
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubVnetName = 'hub-vnet',
    [string]$HubDnsZone = 'azure.pvt',
    [string]$OnpremDnsZone = 'onprem.pvt',
    [string]$HubDnsServerIp = '10.1.10.4'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 6 Validation Tests - Hub DNS Cutover               ║' -ForegroundColor Cyan
Write-Host '║  Final Validation - Complete Migration                    ║' -ForegroundColor Cyan
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
Write-Host "  Hub RG: $HubResourceGroupName" -ForegroundColor White
Write-Host "  Hub VNet: $HubVnetName" -ForegroundColor White
Write-Host "  Hub DNS Server: $HubDnsServerIp" -ForegroundColor White
Write-Host "  Hub Zone: $HubDnsZone" -ForegroundColor White
Write-Host "  On-prem Zone: $OnpremDnsZone" -ForegroundColor White
Write-Host ''

# ================================================
# Hub VNet DNS Configuration
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub VNet DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$vnet = az network vnet show --resource-group $HubResourceGroupName --name $HubVnetName 2>$null | ConvertFrom-Json
Test-Result -Name 'Hub VNet exists' -Success ($null -ne $vnet) -Message 'VNet not found'

if ($vnet) {
    $dnsServers = $vnet.dhcpOptions.dnsServers
    $customDnsConfigured = ($dnsServers -and $dnsServers -contains $HubDnsServerIp)
    Test-Result -Name "Hub VNet DNS configured with $HubDnsServerIp" -Success $customDnsConfigured -Message "DNS servers: $($dnsServers -join ', ')"
    
    $azureDnsStillConfigured = ($null -eq $dnsServers -or $dnsServers.Count -eq 0)
    Test-Result -Name 'Hub VNet no longer uses Azure DNS' -Success (-not $azureDnsStillConfigured) -Message 'VNet still using Azure DNS'
}

# ================================================
# Hub VM DNS Configuration
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub VM DNS Configuration (DHCP)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check DNS VM resolv configuration
Write-Host '  Checking Hub DNS VM configuration...' -ForegroundColor Gray
$dnsVmResolv = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts "resolvectl status 2>&1 | grep 'DNS Servers' | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$dnsVmHasCustomDns = [bool]($dnsVmResolv -match $HubDnsServerIp)
Test-Result -Name "Hub DNS VM using custom DNS ($HubDnsServerIp)" -Success $dnsVmHasCustomDns -Message "Got: $dnsVmResolv"

# Check Client VM resolv configuration
Write-Host '  Checking Hub Client VM configuration...' -ForegroundColor Gray
$clientVmResolv = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "resolvectl status 2>&1 | grep 'DNS Servers' | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$clientVmHasCustomDns = [bool]($clientVmResolv -match $HubDnsServerIp)
Test-Result -Name "Hub Client VM using custom DNS ($HubDnsServerIp)" -Success $clientVmHasCustomDns -Message "Got: $clientVmResolv"

# ================================================
# Hub DNS Resolution - azure.pvt Zone
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub DNS Resolution - azure.pvt Zone' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test resolution from Hub Client VM
Write-Host "  Hub Client VM resolving dns.$HubDnsZone..." -ForegroundColor Gray
$hubClientDnsQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup dns.$HubDnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$hubClientCanResolveDns = [bool]($hubClientDnsQuery -match '10\.1\.10\.4')
Test-Result -Name "Hub Client resolves dns.$HubDnsZone to 10.1.10.4" -Success $hubClientCanResolveDns -Message "Got: $hubClientDnsQuery"

Write-Host "  Hub Client VM resolving client.$HubDnsZone..." -ForegroundColor Gray
$hubClientSelfQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup client.$HubDnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$hubClientCanResolveSelf = [bool]($hubClientSelfQuery -match '10\.1\.10\.5')
Test-Result -Name "Hub Client resolves client.$HubDnsZone to 10.1.10.5" -Success $hubClientCanResolveSelf -Message "Got: $hubClientSelfQuery"

Write-Host "  Hub Client VM resolving ns1.$HubDnsZone..." -ForegroundColor Gray
$hubClientNs1Query = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup ns1.$HubDnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$hubClientCanResolveNs1 = [bool]($hubClientNs1Query -match '10\.1\.10\.4')
Test-Result -Name "Hub Client resolves ns1.$HubDnsZone to 10.1.10.4" -Success $hubClientCanResolveNs1 -Message "Got: $hubClientNs1Query"

# ================================================
# Cross-Environment DNS Resolution
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Cross-Environment DNS Resolution (Bidirectional)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Hub -> On-prem resolution
Write-Host "  Hub Client resolving dns.$OnpremDnsZone (via forwarding)..." -ForegroundColor Gray
$hubToOnpremQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup dns.$OnpremDnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$hubCanResolveOnprem = [bool]($hubToOnpremQuery -match '10\.0\.10\.4')
Test-Result -Name "Hub Client resolves $OnpremDnsZone records" -Success $hubCanResolveOnprem -Message "Got: $hubToOnpremQuery"

# On-prem -> Hub resolution
Write-Host "  On-prem Client resolving dns.$HubDnsZone (via forwarding)..." -ForegroundColor Gray
$onpremToHubQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup dns.$HubDnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$onpremCanResolveHub = [bool]($onpremToHubQuery -match '10\.1\.10\.4')
Test-Result -Name "On-prem Client resolves $HubDnsZone records" -Success $onpremCanResolveHub -Message "Got: $onpremToHubQuery"

# ================================================
# Internet DNS Resolution (Forwarding)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Internet DNS Resolution (via Forwarding)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host '  Hub Client resolving www.microsoft.com...' -ForegroundColor Gray
$hubClientInternetQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nslookup www.microsoft.com 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

# Should get either an IPv4, IPv6, or a CNAME target
$hubClientCanResolveInternet = [bool]($hubClientInternetQuery -match '\d+\.\d+\.\d+\.\d+|[0-9a-fA-F]+:[0-9a-fA-F:]+|[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]')
Test-Result -Name 'Hub Client can resolve internet names' -Success $hubClientCanResolveInternet -Message "Got: $hubClientInternetQuery"

# Test HTTP connectivity
Write-Host '  Testing HTTP connectivity from Hub...' -ForegroundColor Gray
$hubClientHttpTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 10 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$hubClientHasInternet = [bool]($hubClientHttpTest -match '200')
Test-Result -Name 'Hub Client has internet access via custom DNS' -Success $hubClientHasInternet -Message "HTTP response: $hubClientHttpTest"

# ================================================
# DNS Server Accessibility
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Server Accessibility' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test Hub DNS server reachability from Hub client
Write-Host '  Testing Hub DNS port 53 connectivity...' -ForegroundColor Gray
$hubDnsPortTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts "nc -zv -w 2 $HubDnsServerIp 53 2>&1 | grep 'succeeded' && echo 'connected' || echo 'failed'" `
    --query 'value[0].message' -o tsv 2>$null

$hubDnsPortAccessible = [bool]($hubDnsPortTest -match 'connected')
Test-Result -Name "Hub Client can reach Hub DNS server ($HubDnsServerIp:53)" -Success $hubDnsPortAccessible -Message "Connection test: $hubDnsPortTest"

# Verify Hub BIND is running
$hubBindStatus = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$hubBindRunning = [bool]($hubBindStatus -match 'active')
Test-Result -Name 'BIND9 service running on Hub DNS VM' -Success $hubBindRunning -Message "Service status: $hubBindStatus"

# Verify On-prem BIND still running
$onpremBindStatus = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$onpremBindRunning = [bool]($onpremBindStatus -match 'active')
Test-Result -Name 'BIND9 service running on On-prem DNS VM' -Success $onpremBindRunning -Message "Service status: $onpremBindStatus"

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
    Write-Host '  - VMs may need more time for DHCP renewal (wait 5-10 minutes)' -ForegroundColor White
    Write-Host '  - Try manually restarting VMs: az vm restart' -ForegroundColor White
    Write-Host '  - Verify DNS servers are running: systemctl status named' -ForegroundColor White
    Write-Host '  - Check VNet DNS settings in Azure Portal' -ForegroundColor White
    Write-Host '  - Verify VNet peering is connected' -ForegroundColor White
    exit 1
}

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host '✓✓✓ ALL TESTS PASSED - DNS MIGRATION COMPLETE! ✓✓✓' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'Migration Summary:' -ForegroundColor Cyan
Write-Host '  ✓ On-Prem Environment:' -ForegroundColor White
Write-Host '    - VNet uses custom DNS (10.0.10.4)' -ForegroundColor Gray
Write-Host '    - onprem.pvt zone fully operational' -ForegroundColor Gray
Write-Host '    - Can resolve azure.pvt via forwarding' -ForegroundColor Gray
Write-Host ''
Write-Host '  ✓ Hub Environment:' -ForegroundColor White
Write-Host '    - VNet uses custom DNS (10.1.10.4)' -ForegroundColor Gray
Write-Host '    - azure.pvt zone fully operational' -ForegroundColor Gray
Write-Host '    - Can resolve onprem.pvt via forwarding' -ForegroundColor Gray
Write-Host ''
Write-Host '  ✓ Bidirectional DNS:' -ForegroundColor White
Write-Host '    - Hub ↔ On-prem resolution working' -ForegroundColor Gray
Write-Host '    - Internet resolution via Azure DNS' -ForegroundColor Gray
Write-Host '    - All VMs using custom DNS servers' -ForegroundColor Gray
Write-Host ''
Write-Host 'DNS Architecture Achieved:' -ForegroundColor Cyan
Write-Host '  • Isolated private DNS zones (onprem.pvt, azure.pvt)' -ForegroundColor White
Write-Host '  • Bidirectional conditional forwarding' -ForegroundColor White
Write-Host '  • Centralized DNS management per environment' -ForegroundColor White
Write-Host '  • Internet name resolution via Azure DNS' -ForegroundColor White
Write-Host '  • No Azure Private DNS Zones required' -ForegroundColor White
Write-Host ''
Write-Host 'Congratulations! The DNS migration POC is complete.' -ForegroundColor Green
Write-Host ''

exit 0
