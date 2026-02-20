#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 3 on-prem DNS configuration.

.DESCRIPTION
Validates:
- BIND9 is installed and running on on-prem DNS VM
- DNS zone (onprem.pvt) is configured correctly
- DNS records resolve when queried directly
- Forwarding to Azure DNS works for internet names
- VNet still uses Azure DNS (custom DNS not active yet)

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER OnpremDnsVmName
On-prem DNS VM name. Default: onprem-vm-dns

.PARAMETER DnsZone
DNS zone name. Default: onprem.pvt

.EXAMPLE
./phase3-test.ps1
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$OnpremDnsVmName = 'onprem-vm-dns',
    [string]$DnsZone = 'onprem.pvt'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 3 Validation Tests - On-Prem DNS                   ║' -ForegroundColor Cyan
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
Write-Host "  DNS VM: $OnpremDnsVmName" -ForegroundColor White
Write-Host "  Zone: $DnsZone" -ForegroundColor White
Write-Host ''

# ================================================
# BIND9 Installation
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'BIND9 Installation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$bindCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts 'command -v named >/dev/null 2>&1 && echo "installed" || echo "not_found"' `
    --query 'value[0].message' -o tsv 2>$null

$bindInstalled = [bool]($bindCheck -match 'installed')
Test-Result -Name 'BIND9 is installed' -Success $bindInstalled -Message "BIND9 not found on $OnpremDnsVmName"

$serviceCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$serviceRunning = [bool]($serviceCheck -match 'active')
Test-Result -Name 'BIND9 service is running' -Success $serviceRunning -Message "Service status: $serviceCheck"

# ================================================
# DNS Zone Configuration
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Zone Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check zone file exists
$zoneFileCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "test -f /etc/bind/db.$DnsZone && echo 'exists' || echo 'not_found'" `
    --query 'value[0].message' -o tsv 2>$null

$zoneFileExists = [bool]($zoneFileCheck -match 'exists')
Test-Result -Name "Zone file exists (/etc/bind/db.$DnsZone)" -Success $zoneFileExists -Message 'Zone file not found'

# Validate zone configuration (try multiple binary paths)
$zoneCheckCmd = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; sudo /usr/sbin/named-checkzone $DnsZone /etc/bind/db.$DnsZone 2>&1 || sudo /usr/bin/named-checkzone $DnsZone /etc/bind/db.$DnsZone 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$zoneValid = [bool]($zoneCheckCmd -match 'OK')
Test-Result -Name "Zone $DnsZone validates correctly" -Success $zoneValid -Message "Validation: $zoneCheckCmd"

# ================================================
# DNS Record Resolution (Direct Queries)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Record Resolution (Direct Query to Server)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Query dns.onprem.pvt
Write-Host "  Querying: dns.$DnsZone..." -ForegroundColor Gray
$dnsQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$DnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$dnsResolved = [bool]($dnsQuery -match '10\.0\.10\.4')
Test-Result -Name "dns.$DnsZone resolves to 10.0.10.4" -Success $dnsResolved -Message "Got: $dnsQuery"

# Query client.onprem.pvt
Write-Host "  Querying: client.$DnsZone..." -ForegroundColor Gray
$clientQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 client.$DnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$clientResolved = [bool]($clientQuery -match '10\.0\.10\.5')
Test-Result -Name "client.$DnsZone resolves to 10.0.10.5" -Success $clientResolved -Message "Got: $clientQuery"

# Query ns1.onprem.pvt
Write-Host "  Querying: ns1.$DnsZone..." -ForegroundColor Gray
$ns1Query = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 ns1.$DnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$ns1Resolved = [bool]($ns1Query -match '10\.0\.10\.4')
Test-Result -Name "ns1.$DnsZone resolves to 10.0.10.4" -Success $ns1Resolved -Message "Got: $ns1Query"

# ================================================
# DNS Forwarding (Internet Names)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Forwarding to Azure DNS' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Query internet name through the DNS server
Write-Host '  Querying: www.microsoft.com...' -ForegroundColor Gray
$forwardQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 www.microsoft.com +short 2>&1 | head -1" `
    --query 'value[0].message' -o tsv 2>$null

# Should get an IP address or CNAME (any valid DNS response means forwarding works)
$forwardingWorks = [bool]($forwardQuery -match '\d+\.\d+\.\d+\.\d+|[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]')
Test-Result -Name 'Forwarding to Azure DNS works (www.microsoft.com)' -Success $forwardingWorks -Message "Got: $forwardQuery"

# ================================================
# VNet DNS Configuration (Should Still Be Azure DNS)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$vnet = az network vnet show --resource-group $OnpremResourceGroupName --name 'onprem-vnet' 2>$null | ConvertFrom-Json
$dnsServers = $vnet.dhcpOptions.dnsServers
$stillUsingAzureDns = ($null -eq $dnsServers) -or ($dnsServers.Count -eq 0)

Test-Result -Name 'VNet still uses Azure DNS (custom DNS not active)' -Success $stillUsingAzureDns -Message "VNet DNS: $($dnsServers -join ', ')"

# Verify client VM still uses Azure DNS by checking resolv.conf
Write-Host '  Checking client VM resolv.conf...' -ForegroundColor Gray
$clientResolvConf = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'cat /etc/resolv.conf | grep nameserver' `
    --query 'value[0].message' -o tsv 2>$null

$clientUsesAzureDns = [bool]($clientResolvConf -match '127\.0\.0\.53')
Test-Result -Name 'Client VM still uses Azure DNS (via systemd-resolved)' -Success $clientUsesAzureDns -Message "resolv.conf: $clientResolvConf"

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
    Write-Host '  - BIND9 may not have restarted correctly (check systemctl status)' -ForegroundColor White
    Write-Host '  - Zone file syntax errors (check named-checkzone output)' -ForegroundColor White
    Write-Host '  - Firewall blocking DNS queries (check UFW status)' -ForegroundColor White
    exit 1
}

Write-Host '✓ All tests passed! On-Prem DNS is configured correctly.' -ForegroundColor Green
Write-Host ''
Write-Host 'Key Points:' -ForegroundColor Cyan
Write-Host '  • DNS server (10.0.10.4) is running and answering queries' -ForegroundColor White
Write-Host "  • Zone $DnsZone is configured with correct records" -ForegroundColor White
Write-Host '  • Forwarding to Azure DNS (168.63.129.16) works' -ForegroundColor White
Write-Host '  • VNet/VMs still use Azure DNS (custom DNS not active yet)' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  Ready for Phase 4: Switch VNet to use custom DNS' -ForegroundColor White
Write-Host ''
Write-Host '  Phase 4 will:' -ForegroundColor Gray
Write-Host '    - Update VNet DNS setting to 10.0.10.4' -ForegroundColor Gray
Write-Host '    - Restart VMs to acquire new DNS settings' -ForegroundColor Gray
Write-Host "    - Enable resolution of $DnsZone from all on-prem VMs" -ForegroundColor Gray
Write-Host ''

exit 0
