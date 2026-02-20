#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 4 on-prem DNS cutover.

.DESCRIPTION
Validates:
- VNet DNS settings point to custom DNS server (10.0.10.4)
- VMs have acquired new DNS settings via DHCP
- VMs can resolve onprem.pvt records using custom DNS
- Internet resolution still works through DNS forwarding
- DNS server is accessible from VMs

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER OnpremVnetName
On-prem VNet name. Default: onprem-vnet

.PARAMETER DnsZone
DNS zone name. Default: onprem.pvt

.PARAMETER DnsServerIp
DNS server IP address. Default: 10.0.10.4

.EXAMPLE
./phase4-test.ps1
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$OnpremVnetName = 'onprem-vnet',
    [string]$DnsZone = 'onprem.pvt',
    [string]$DnsServerIp = '10.0.10.4'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 4 Validation Tests - On-Prem DNS Cutover           ║' -ForegroundColor Cyan
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
Write-Host "  VNet: $OnpremVnetName" -ForegroundColor White
Write-Host "  DNS Server: $DnsServerIp" -ForegroundColor White
Write-Host "  Zone: $DnsZone" -ForegroundColor White
Write-Host ''

# ================================================
# VNet DNS Configuration
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$vnet = az network vnet show --resource-group $OnpremResourceGroupName --name $OnpremVnetName 2>$null | ConvertFrom-Json
Test-Result -Name 'VNet exists' -Success ($null -ne $vnet) -Message 'VNet not found'

if ($vnet) {
    $dnsServers = $vnet.dhcpOptions.dnsServers
    $customDnsConfigured = ($dnsServers -and $dnsServers -contains $DnsServerIp)
    Test-Result -Name "VNet DNS configured with $DnsServerIp" -Success $customDnsConfigured -Message "DNS servers: $($dnsServers -join ', ')"
    
    $azureDnsStillConfigured = ($null -eq $dnsServers -or $dnsServers.Count -eq 0)
    Test-Result -Name 'VNet no longer uses Azure DNS' -Success (-not $azureDnsStillConfigured) -Message 'VNet still using Azure DNS'
}

# ================================================
# VM DNS Configuration
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VM DNS Configuration (DHCP)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check DNS VM resolv configuration
Write-Host '  Checking DNS VM configuration...' -ForegroundColor Gray
$dnsVmResolv = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts "resolvectl status 2>&1 | grep 'DNS Servers' | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$dnsVmHasCustomDns = [bool]($dnsVmResolv -match $DnsServerIp)
Test-Result -Name "DNS VM using custom DNS ($DnsServerIp)" -Success $dnsVmHasCustomDns -Message "Got: $dnsVmResolv"

# Check Client VM resolv configuration
Write-Host '  Checking Client VM configuration...' -ForegroundColor Gray
$clientVmResolv = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "resolvectl status 2>&1 | grep 'DNS Servers' | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$clientVmHasCustomDns = [bool]($clientVmResolv -match $DnsServerIp)
Test-Result -Name "Client VM using custom DNS ($DnsServerIp)" -Success $clientVmHasCustomDns -Message "Got: $clientVmResolv"

# ================================================
# DNS Resolution from VMs (onprem.pvt zone)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Resolution - onprem.pvt Zone' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test resolution from Client VM (using system resolver, not direct query)
Write-Host "  Client VM resolving dns.$DnsZone..." -ForegroundColor Gray
$clientDnsQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup dns.$DnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$clientCanResolveDns = [bool]($clientDnsQuery -match '10\.0\.10\.4')
Test-Result -Name "Client VM resolves dns.$DnsZone to 10.0.10.4" -Success $clientCanResolveDns -Message "Got: $clientDnsQuery"

Write-Host "  Client VM resolving client.$DnsZone..." -ForegroundColor Gray
$clientSelfQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup client.$DnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$clientCanResolveSelf = [bool]($clientSelfQuery -match '10\.0\.10\.5')
Test-Result -Name "Client VM resolves client.$DnsZone to 10.0.10.5" -Success $clientCanResolveSelf -Message "Got: $clientSelfQuery"

Write-Host "  Client VM resolving ns1.$DnsZone..." -ForegroundColor Gray
$clientNs1Query = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup ns1.$DnsZone 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

$clientCanResolveNs1 = [bool]($clientNs1Query -match '10\.0\.10\.4')
Test-Result -Name "Client VM resolves ns1.$DnsZone to 10.0.10.4" -Success $clientCanResolveNs1 -Message "Got: $clientNs1Query"

# ================================================
# Internet DNS Resolution (Forwarding)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Internet DNS Resolution (via Forwarding)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host '  Client VM resolving www.microsoft.com...' -ForegroundColor Gray
$clientInternetQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nslookup www.microsoft.com 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
    --query 'value[0].message' -o tsv 2>$null

# Should get either an IPv4, IPv6, or a CNAME target that looks like a domain
$clientCanResolveInternet = [bool]($clientInternetQuery -match '\d+\.\d+\.\d+\.\d+|[0-9a-fA-F]+:[0-9a-fA-F:]+|[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]')
Test-Result -Name 'Client VM can resolve internet names (www.microsoft.com)' -Success $clientCanResolveInternet -Message "Got: $clientInternetQuery"

# Test HTTP connectivity to verify full internet access
Write-Host '  Testing HTTP connectivity...' -ForegroundColor Gray
$clientHttpTest = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 10 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$clientHasInternet = [bool]($clientHttpTest -match '200')
Test-Result -Name 'Client VM has internet access via custom DNS' -Success $clientHasInternet -Message "HTTP response: $clientHttpTest"

# ================================================
# DNS Server Accessibility
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Server Accessibility' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test DNS server reachability from client
Write-Host '  Testing DNS port 53 connectivity...' -ForegroundColor Gray
$dnsPortTest = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts "nc -zv -w 2 $DnsServerIp 53 2>&1 | grep 'succeeded' && echo 'connected' || echo 'failed'" `
    --query 'value[0].message' -o tsv 2>$null

$dnsPortAccessible = [bool]($dnsPortTest -match 'connected')
Test-Result -Name "Client can reach DNS server port 53 ($DnsServerIp:53)" -Success $dnsPortAccessible -Message "Connection test: $dnsPortTest"

# Verify BIND is running
$bindStatus = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$bindRunning = [bool]($bindStatus -match 'active')
Test-Result -Name 'BIND9 service is running on DNS VM' -Success $bindRunning -Message "Service status: $bindStatus"

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
    Write-Host '  - Verify DNS server is running: systemctl status named' -ForegroundColor White
    Write-Host '  - Check VNet DNS settings in Azure Portal' -ForegroundColor White
    exit 1
}

Write-Host '✓ All tests passed! On-Prem DNS cutover is successful.' -ForegroundColor Green
Write-Host ''
Write-Host 'Key Points:' -ForegroundColor Cyan
Write-Host "  • VNet configured to use custom DNS ($DnsServerIp)" -ForegroundColor White
Write-Host '  • VMs have acquired new DNS settings via DHCP' -ForegroundColor White
Write-Host "  • VMs can resolve $DnsZone records" -ForegroundColor White
Write-Host '  • Internet resolution works via forwarding to Azure DNS' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  Ready for Phase 5: Configure Hub DNS server' -ForegroundColor White
Write-Host ''
Write-Host '  Phase 5 will:' -ForegroundColor Gray
Write-Host '    - Install BIND9 on hub-vm-dns (10.1.10.4)' -ForegroundColor Gray
Write-Host '    - Configure azure.pvt zone' -ForegroundColor Gray
Write-Host '    - Set up bidirectional DNS forwarding with on-prem' -ForegroundColor Gray
Write-Host ''

exit 0
