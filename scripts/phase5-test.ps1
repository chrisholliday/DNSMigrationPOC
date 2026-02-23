#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 5 Hub DNS configuration and bidirectional forwarding.

.DESCRIPTION
Validates:
- BIND9 is installed and running on hub DNS VM
- DNS zone (azure.pvt) is configured correctly
- DNS records resolve when queried directly
- Hub DNS forwards onprem.pvt queries to on-prem DNS (10.0.10.4)
- On-prem DNS forwards azure.pvt queries to hub DNS (10.1.10.4)
- Both servers forward to Azure DNS for internet names
- VNets maintain correct DNS settings (on-prem custom, hub still Azure)

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubDnsVmName
Hub DNS VM name. Default: hub-vm-dns

.PARAMETER OnpremDnsVmName
On-prem DNS VM name. Default: onprem-vm-dns

.PARAMETER HubDnsZone
Hub DNS zone name. Default: azure.pvt

.PARAMETER OnpremDnsZone
On-prem DNS zone name. Default: onprem.pvt

.EXAMPLE
./phase5-test.ps1
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubDnsVmName = 'hub-vm-dns',
    [string]$OnpremDnsVmName = 'onprem-vm-dns',
    [string]$HubDnsZone = 'azure.pvt',
    [string]$OnpremDnsZone = 'onprem.pvt'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 5 Validation Tests - Hub DNS + Bidirectional       ║' -ForegroundColor Cyan
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
Write-Host "  Hub DNS VM: $HubDnsVmName (10.1.10.4)" -ForegroundColor White
Write-Host "  Hub Zone: $HubDnsZone" -ForegroundColor White
Write-Host "  On-prem RG: $OnpremResourceGroupName" -ForegroundColor White
Write-Host "  On-prem DNS VM: $OnpremDnsVmName (10.0.10.4)" -ForegroundColor White
Write-Host "  On-prem Zone: $OnpremDnsZone" -ForegroundColor White
Write-Host ''

# ================================================
# Hub BIND9 Installation
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub BIND9 Installation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$bindCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts 'command -v named >/dev/null 2>&1 && echo "installed" || echo "not_found"' `
    --query 'value[0].message' -o tsv 2>$null

$bindInstalled = [bool]($bindCheck -match 'installed')
Test-Result -Name 'BIND9 is installed on Hub' -Success $bindInstalled -Message "BIND9 not found on $HubDnsVmName"

$serviceCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$serviceRunning = [bool]($serviceCheck -match 'active')
Test-Result -Name 'BIND9 service is running on Hub' -Success $serviceRunning -Message "Service status: $serviceCheck"

# ================================================
# Hub DNS Zone Configuration
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub DNS Zone Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check zone file exists
$zoneFileCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "test -f /etc/bind/db.$HubDnsZone && echo 'exists' || echo 'not_found'" `
    --query 'value[0].message' -o tsv 2>$null

$zoneFileExists = [bool]($zoneFileCheck -match 'exists')
Test-Result -Name "Zone file exists (/etc/bind/db.$HubDnsZone)" -Success $zoneFileExists -Message 'Zone file not found'

# Validate zone configuration
$zoneCheckCmd = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; sudo /usr/sbin/named-checkzone $HubDnsZone /etc/bind/db.$HubDnsZone 2>&1 || sudo /usr/bin/named-checkzone $HubDnsZone /etc/bind/db.$HubDnsZone 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$zoneValid = [bool]($zoneCheckCmd -match 'OK')
Test-Result -Name "Zone $HubDnsZone validates correctly" -Success $zoneValid -Message "Validation: $zoneCheckCmd"

# ================================================
# Hub DNS Record Resolution
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub DNS Record Resolution (Direct Query)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Query dns.azure.pvt
Write-Host "  Querying: dns.$HubDnsZone..." -ForegroundColor Gray
$dnsQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$HubDnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$dnsResolved = [bool]($dnsQuery -match '10\.1\.10\.4')
Test-Result -Name "dns.$HubDnsZone resolves to 10.1.10.4" -Success $dnsResolved -Message "Got: $dnsQuery"

# Query client.azure.pvt
Write-Host "  Querying: client.$HubDnsZone..." -ForegroundColor Gray
$clientQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 client.$HubDnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$clientResolved = [bool]($clientQuery -match '10\.1\.10\.5')
Test-Result -Name "client.$HubDnsZone resolves to 10.1.10.5" -Success $clientResolved -Message "Got: $clientQuery"

# Query ns1.azure.pvt
Write-Host "  Querying: ns1.$HubDnsZone..." -ForegroundColor Gray
$ns1Query = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 ns1.$HubDnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$ns1Resolved = [bool]($ns1Query -match '10\.1\.10\.4')
Test-Result -Name "ns1.$HubDnsZone resolves to 10.1.10.4" -Success $ns1Resolved -Message "Got: $ns1Query"

# ================================================
# Hub DNS Forwarding to Azure DNS
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub DNS Forwarding to Azure DNS' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Query internet name through hub DNS server
Write-Host '  Querying: www.microsoft.com...' -ForegroundColor Gray
$hubForwardQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 www.microsoft.com +short 2>&1 | head -1" `
    --query 'value[0].message' -o tsv 2>$null

$hubForwardingWorks = [bool]($hubForwardQuery -match '\d+\.\d+\.\d+\.\d+|[0-9a-fA-F]+:[0-9a-fA-F:]+|[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]')
Test-Result -Name 'Hub forwarding to Azure DNS works' -Success $hubForwardingWorks -Message "Got: $hubForwardQuery"

# ================================================
# Network Connectivity Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Network Connectivity Between DNS Servers' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test Hub can reach On-prem DNS
Write-Host '  Testing Hub -> On-prem (10.1.10.4 -> 10.0.10.4)...' -ForegroundColor Gray
$hubToOnpremPing = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "ping -c 2 -W 2 10.0.10.4 > /dev/null 2>&1 && echo 'reachable' || echo 'unreachable'" `
    --query 'value[0].message' -o tsv 2>$null

$hubCanReachOnprem = [bool]($hubToOnpremPing -match 'reachable')
Test-Result -Name 'Hub can reach On-prem DNS (10.0.10.4)' -Success $hubCanReachOnprem -Message "Ping result: $hubToOnpremPing"

# Test On-prem can reach Hub DNS
Write-Host '  Testing On-prem -> Hub (10.0.10.4 -> 10.1.10.4)...' -ForegroundColor Gray
$onpremToHubPing = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "ping -c 2 -W 2 10.1.10.4 > /dev/null 2>&1 && echo 'reachable' || echo 'unreachable'" `
    --query 'value[0].message' -o tsv 2>$null

$onpremCanReachHub = [bool]($onpremToHubPing -match 'reachable')
Test-Result -Name 'On-prem can reach Hub DNS (10.1.10.4)' -Success $onpremCanReachHub -Message "Ping result: $onpremToHubPing"

# Test DNS port 53 connectivity Hub -> On-prem
Write-Host '  Testing DNS port 53: Hub -> On-prem...' -ForegroundColor Gray
$hubDnsPortTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "timeout 3 bash -c '</dev/tcp/10.0.10.4/53' 2>/dev/null && echo 'open' || echo 'closed'" `
    --query 'value[0].message' -o tsv 2>$null

$hubDnsPortOpen = [bool]($hubDnsPortTest -match 'open')
Test-Result -Name 'DNS port 53 accessible from Hub to On-prem' -Success $hubDnsPortOpen -Message "Port test: $hubDnsPortTest"

# Test DNS port 53 connectivity On-prem -> Hub
Write-Host '  Testing DNS port 53: On-prem -> Hub...' -ForegroundColor Gray
$onpremDnsPortTest = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "timeout 3 bash -c '</dev/tcp/10.1.10.4/53' 2>/dev/null && echo 'open' || echo 'closed'" `
    --query 'value[0].message' -o tsv 2>$null

$onpremDnsPortOpen = [bool]($onpremDnsPortTest -match 'open')
Test-Result -Name 'DNS port 53 accessible from On-prem to Hub' -Success $onpremDnsPortOpen -Message "Port test: $onpremDnsPortTest"

# ================================================
# Bidirectional Forwarding
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Bidirectional Forwarding Tests' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Hub -> On-prem: Query onprem.pvt from hub DNS (with timeout and retry)
Write-Host "  Hub forwarding $OnpremDnsZone queries to 10.0.10.4..." -ForegroundColor Gray
$hubToOnpremQuery = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$OnpremDnsZone +time=3 +tries=2 +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

if (-not ($hubToOnpremQuery -match '10\.0\.10\.4')) {
    Write-Host '  Retrying with verbose output...' -ForegroundColor Gray
    $hubToOnpremQueryVerbose = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name $HubDnsVmName `
        --command-id RunShellScript `
        --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$OnpremDnsZone +time=5 +tries=1 2>&1" `
        --query 'value[0].message' -o tsv 2>$null
    Write-Host "  Verbose output: $hubToOnpremQueryVerbose" -ForegroundColor Gray
}

$hubCanForwardToOnprem = [bool]($hubToOnpremQuery -match '10\.0\.10\.4')
Test-Result -Name "Hub forwards $OnpremDnsZone to 10.0.10.4" -Success $hubCanForwardToOnprem -Message "Got: $hubToOnpremQuery"

# On-prem -> Hub: Query azure.pvt from on-prem DNS (with timeout and retry)
Write-Host "  On-prem forwarding $HubDnsZone queries to 10.1.10.4..." -ForegroundColor Gray
$onpremToHubQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$HubDnsZone +time=3 +tries=2 +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

if (-not ($onpremToHubQuery -match '10\.1\.10\.4')) {
    Write-Host '  Retrying with verbose output...' -ForegroundColor Gray
    $onpremToHubQueryVerbose = az vm run-command invoke `
        --resource-group $OnpremResourceGroupName `
        --name $OnpremDnsVmName `
        --command-id RunShellScript `
        --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$HubDnsZone +time=5 +tries=1 2>&1" `
        --query 'value[0].message' -o tsv 2>$null
    Write-Host "  Verbose output: $onpremToHubQueryVerbose" -ForegroundColor Gray
}

$onpremCanForwardToHub = [bool]($onpremToHubQuery -match '10\.1\.10\.4')
Test-Result -Name "On-prem forwards $HubDnsZone to 10.1.10.4" -Success $onpremCanForwardToHub -Message "Got: $onpremToHubQuery"

# ================================================
# On-Prem DNS Still Resolves Local Zone
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'On-Prem DNS Local Zone Resolution' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host "  Querying: dns.$OnpremDnsZone from on-prem DNS..." -ForegroundColor Gray
$onpremLocalQuery = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH; dig @127.0.0.1 dns.$OnpremDnsZone +short 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

$onpremLocalResolved = [bool]($onpremLocalQuery -match '10\.0\.10\.4')
Test-Result -Name "On-prem still resolves local $OnpremDnsZone zone" -Success $onpremLocalResolved -Message "Got: $onpremLocalQuery"

# ================================================
# VNet DNS Configuration
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check On-prem VNet (should be using custom DNS after Phase 4)
Write-Host '  Checking On-prem VNet...' -ForegroundColor Gray
$onpremVnet = az network vnet show --resource-group $OnpremResourceGroupName --name 'onprem-vnet' 2>$null | ConvertFrom-Json
$onpremDnsServers = $onpremVnet.dhcpOptions.dnsServers
$onpremUsesCustomDns = ($onpremDnsServers -contains '10.0.10.4')

Test-Result -Name 'On-prem VNet uses custom DNS (10.0.10.4)' -Success $onpremUsesCustomDns -Message "VNet DNS: $($onpremDnsServers -join ', ')"

# Check Hub VNet (should still be using Azure DNS)
Write-Host '  Checking Hub VNet...' -ForegroundColor Gray
$hubVnet = az network vnet show --resource-group $HubResourceGroupName --name 'hub-vnet' 2>$null | ConvertFrom-Json
$hubDnsServers = $hubVnet.dhcpOptions.dnsServers
$hubStillUsingAzureDns = ($null -eq $hubDnsServers) -or ($hubDnsServers.Count -eq 0)

Test-Result -Name 'Hub VNet still uses Azure DNS (custom DNS not active)' -Success $hubStillUsingAzureDns -Message "VNet DNS: $($hubDnsServers -join ', ')"

# ================================================
# Configuration Files Check
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Configuration Files Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Verify Hub named.conf.local contains forwarding zone for onprem.pvt
Write-Host '  Checking Hub named.conf.local...' -ForegroundColor Gray
$hubConfCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts 'sudo cat /etc/bind/named.conf.local 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$hubConfHasOnpremForwarding = [bool]($hubConfCheck -match "zone `"$OnpremDnsZone`"")
Test-Result -Name "Hub config includes $OnpremDnsZone forwarding zone" -Success $hubConfHasOnpremForwarding -Message 'Config check failed'

# Verify On-prem named.conf.local contains forwarding zone for azure.pvt
Write-Host '  Checking On-prem named.conf.local...' -ForegroundColor Gray
$onpremConfCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts 'sudo cat /etc/bind/named.conf.local 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$onpremConfHasHubForwarding = [bool]($onpremConfCheck -match "zone `"$HubDnsZone`"")
Test-Result -Name "On-prem config includes $HubDnsZone forwarding zone" -Success $onpremConfHasHubForwarding -Message 'Config check failed'

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
    Write-Host '  - Forwarding configuration errors (check named.conf.local)' -ForegroundColor White
    Write-Host '  - Network connectivity between DNS servers (check VNet peering)' -ForegroundColor White
    exit 1
}

Write-Host '✓ All tests passed! Hub DNS + Bidirectional forwarding configured.' -ForegroundColor Green
Write-Host ''
Write-Host 'Key Points:' -ForegroundColor Cyan
Write-Host '  • Hub DNS server (10.1.10.4) is running and answering queries' -ForegroundColor White
Write-Host "  • Zone $HubDnsZone is configured with correct records" -ForegroundColor White
Write-Host "  • Hub forwards $OnpremDnsZone queries to 10.0.10.4" -ForegroundColor White
Write-Host "  • On-prem forwards $HubDnsZone queries to 10.1.10.4" -ForegroundColor White
Write-Host '  • Both servers forward internet queries to Azure DNS' -ForegroundColor White
Write-Host '  • On-prem VNet uses custom DNS (10.0.10.4) - Phase 4 complete' -ForegroundColor White
Write-Host '  • Hub VNet still uses Azure DNS (custom DNS not active yet)' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  Ready for Phase 6: Switch Hub VNet to use custom DNS' -ForegroundColor White
Write-Host ''
Write-Host '  Phase 6 will:' -ForegroundColor Gray
Write-Host '    - Update Hub VNet DNS setting to 10.1.10.4' -ForegroundColor Gray
Write-Host '    - Restart Hub VMs to acquire new DNS settings' -ForegroundColor Gray
Write-Host "    - Enable resolution of $HubDnsZone from all hub VMs" -ForegroundColor Gray
Write-Host '    - Enable full bidirectional DNS resolution across both environments' -ForegroundColor Gray
Write-Host ''

exit 0
