#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 7 deployment - Spoke networks and storage accounts.

.DESCRIPTION
Validates:
- Spoke VNets exist and are properly configured
- VNet peering established (Hub <-> Spoke1, Hub <-> Spoke2)
- Storage accounts deployed with private endpoints
- DNS zone for privatelink.blob.core.windows.net configured on hub-vm-dns
- All environments can resolve storage account privatelink names
- Cross-VNet connectivity works

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER Spoke1ResourceGroupName
Spoke1 resource group name. Default: rg-spoke1-dnsmig

.PARAMETER Spoke2ResourceGroupName
Spoke2 resource group name. Default: rg-spoke2-dnsmig

.EXAMPLE
./scripts/phase7-test.ps1
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$Spoke1ResourceGroupName = 'rg-spoke1-dnsmig',
    [string]$Spoke2ResourceGroupName = 'rg-spoke2-dnsmig'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 7 Validation Tests                                 ║' -ForegroundColor Cyan
Write-Host '║  Spoke Networks & Storage                                 ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Host 'Configuration:' -ForegroundColor Cyan
Write-Host "  Hub RG: $HubResourceGroupName" -ForegroundColor Gray
Write-Host "  On-prem RG: $OnpremResourceGroupName" -ForegroundColor Gray
Write-Host "  Spoke1 RG: $Spoke1ResourceGroupName" -ForegroundColor Gray
Write-Host "  Spoke2 RG: $Spoke2ResourceGroupName" -ForegroundColor Gray
Write-Host ''

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ''
    )
    
    if ($Success) {
        Write-Host "[TEST] $Name" -ForegroundColor White
        Write-Host '  ✓ PASS' -ForegroundColor Green
        $script:passCount++
    }
    else {
        Write-Host "[TEST] $Name" -ForegroundColor White
        Write-Host '  ✗ FAIL' -ForegroundColor Red
        if ($Message) {
            Write-Host "    $Message" -ForegroundColor Yellow
        }
        $script:failCount++
    }
}

# ================================================
# Infrastructure Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Spoke Infrastructure' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check Spoke1 VNet
$spoke1Vnet = az network vnet show `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-vnet' `
    --query 'name' -o tsv 2>$null

Test-Result -Name 'Spoke1 VNet exists' -Success ($spoke1Vnet -eq 'spoke1-vnet')

# Check Spoke1 VNet DNS configuration
$spoke1Dns = az network vnet show `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-vnet' `
    --query 'dhcpOptions.dnsServers[0]' -o tsv 2>$null

Test-Result -Name 'Spoke1 VNet DNS configured (10.1.10.4)' -Success ($spoke1Dns -eq '10.1.10.4')

# Check Spoke2 VNet
$spoke2Vnet = az network vnet show `
    --resource-group $Spoke2ResourceGroupName `
    --name 'spoke2-vnet' `
    --query 'name' -o tsv 2>$null

Test-Result -Name 'Spoke2 VNet exists' -Success ($spoke2Vnet -eq 'spoke2-vnet')

# Check Spoke2 VNet DNS configuration
$spoke2Dns = az network vnet show `
    --resource-group $Spoke2ResourceGroupName `
    --name 'spoke2-vnet' `
    --query 'dhcpOptions.dnsServers[0]' -o tsv 2>$null

Test-Result -Name 'Spoke2 VNet DNS configured (10.1.10.4)' -Success ($spoke2Dns -eq '10.1.10.4')

# ================================================
# VNet Peering Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet Peering' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Hub to Spoke1
$hubToSpoke1 = az network vnet peering show `
    --resource-group $HubResourceGroupName `
    --name 'hub-to-spoke1' `
    --vnet-name 'hub-vnet' `
    --query 'peeringState' -o tsv 2>$null

Test-Result -Name 'Hub to Spoke1 peering connected' -Success ($hubToSpoke1 -eq 'Connected')

# Spoke1 to Hub
$spoke1ToHub = az network vnet peering show `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-to-hub' `
    --vnet-name 'spoke1-vnet' `
    --query 'peeringState' -o tsv 2>$null

Test-Result -Name 'Spoke1 to Hub peering connected' -Success ($spoke1ToHub -eq 'Connected')

# Hub to Spoke2
$hubToSpoke2 = az network vnet peering show `
    --resource-group $HubResourceGroupName `
    --name 'hub-to-spoke2' `
    --vnet-name 'hub-vnet' `
    --query 'peeringState' -o tsv 2>$null

Test-Result -Name 'Hub to Spoke2 peering connected' -Success ($hubToSpoke2 -eq 'Connected')

# Spoke2 to Hub
$spoke2ToHub = az network vnet peering show `
    --resource-group $Spoke2ResourceGroupName `
    --name 'spoke2-to-hub' `
    --vnet-name 'spoke2-vnet' `
    --query 'peeringState' -o tsv 2>$null

Test-Result -Name 'Spoke2 to Hub peering connected' -Success ($spoke2ToHub -eq 'Connected')

# ================================================
# Storage and Private Endpoint Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Storage Accounts & Private Endpoints' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Get storage account names
$spoke1Storage = az storage account list `
    --resource-group $Spoke1ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

$spoke2Storage = az storage account list `
    --resource-group $Spoke2ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

Test-Result -Name 'Spoke1 storage account exists' -Success ($null -ne $spoke1Storage)
Test-Result -Name 'Spoke2 storage account exists' -Success ($null -ne $spoke2Storage)

if ($spoke1Storage) {
    Write-Host "    Spoke1 Storage: $spoke1Storage" -ForegroundColor Gray
}
if ($spoke2Storage) {
    Write-Host "    Spoke2 Storage: $spoke2Storage" -ForegroundColor Gray
}

# Check private endpoints
$spoke1PE = az network private-endpoint list `
    --resource-group $Spoke1ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

$spoke2PE = az network private-endpoint list `
    --resource-group $Spoke2ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

Test-Result -Name 'Spoke1 private endpoint exists' -Success ($null -ne $spoke1PE)
Test-Result -Name 'Spoke2 private endpoint exists' -Success ($null -ne $spoke2PE)

# ================================================
# Hub DNS Configuration Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Hub DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Check if blob.core.windows.net zone is configured
Write-Host '  Checking BIND9 configuration...' -ForegroundColor Gray
$blobZoneCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'grep -c "zone \"blob.core.windows.net\"" /etc/bind/named.conf.local' `
    --query 'value[0].message' -o tsv 2>$null

$blobZoneConfigured = [bool]($blobZoneCheck -match '^1')
Test-Result -Name 'Blob zone configured in named.conf.local' -Success $blobZoneConfigured

# Check if privatelink zone is configured
$privatelinkZoneCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'grep -c "zone \"privatelink.blob.core.windows.net\"" /etc/bind/named.conf.local' `
    --query 'value[0].message' -o tsv 2>$null

$privatelinkZoneConfigured = [bool]($privatelinkZoneCheck -match '^1')
Test-Result -Name 'Privatelink zone configured in named.conf.local' -Success $privatelinkZoneConfigured

# Check if blob zone file exists
$blobZoneFileCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'test -f /etc/bind/db.blob.core.windows.net && echo "EXISTS" || echo "MISSING"' `
    --query 'value[0].message' -o tsv 2>$null

$blobZoneFileExists = [bool]($blobZoneFileCheck -match 'EXISTS')
Test-Result -Name 'Blob zone file exists' -Success $blobZoneFileExists

# Check if privatelink zone file exists
$zoneFileCheck = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'test -f /etc/bind/db.privatelink.blob.core.windows.net && echo "EXISTS" || echo "MISSING"' `
    --query 'value[0].message' -o tsv 2>$null

$zoneFileExists = [bool]($zoneFileCheck -match 'EXISTS')
Test-Result -Name 'Privatelink zone file exists' -Success $zoneFileExists

# Check BIND9 is running
$bindStatus = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl is-active bind9' `
    --query 'value[0].message' -o tsv 2>$null

$bindRunning = [bool]($bindStatus -match 'active')
Test-Result -Name 'BIND9 service running on hub-vm-dns' -Success $bindRunning

# ================================================
# DNS Resolution Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS Resolution Tests' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

if ($spoke1Storage -and $spoke2Storage) {
    # Build FQDNs
    $spoke1Fqdn = "$spoke1Storage.blob.core.windows.net"
    $spoke2Fqdn = "$spoke2Storage.blob.core.windows.net"
    
    Write-Host '  Testing resolution of:' -ForegroundColor Gray
    Write-Host "    $spoke1Fqdn" -ForegroundColor Gray
    Write-Host "    $spoke2Fqdn" -ForegroundColor Gray
    Write-Host ''
    
    # Test from Hub VM
    Write-Host '  Testing from Hub VM...' -ForegroundColor Gray
    $hubResolveSpoke1 = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name 'hub-vm-app' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke1Fqdn 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
        --query 'value[0].message' -o tsv 2>$null
    
    $hubResolveSpoke1Str = if ($hubResolveSpoke1) { [string]$hubResolveSpoke1 } else { '' }
    $hubCanResolve1 = [bool]($hubResolveSpoke1Str -match '10\.2\.')
    Test-Result -Name 'Hub VM resolves Spoke1 storage' -Success $hubCanResolve1 -Message "Got: $hubResolveSpoke1Str"
    
    $hubResolveSpoke2 = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name 'hub-vm-app' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke2Fqdn 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
        --query 'value[0].message' -o tsv 2>$null
    
    $hubResolveSpoke2Str = if ($hubResolveSpoke2) { [string]$hubResolveSpoke2 } else { '' }
    $hubCanResolve2 = [bool]($hubResolveSpoke2Str -match '10\.3\.')
    Test-Result -Name 'Hub VM resolves Spoke2 storage' -Success $hubCanResolve2 -Message "Got: $hubResolveSpoke2Str"
    
    # Test from On-prem VM
    Write-Host '  Testing from On-prem VM...' -ForegroundColor Gray
    $onpremResolveSpoke1 = az vm run-command invoke `
        --resource-group $OnpremResourceGroupName `
        --name 'onprem-vm-client' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke1Fqdn 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
        --query 'value[0].message' -o tsv 2>$null
    
    $onpremResolveSpoke1Str = if ($onpremResolveSpoke1) { [string]$onpremResolveSpoke1 } else { '' }
    $onpremCanResolve1 = [bool]($onpremResolveSpoke1Str -match '10\.2\.')
    Test-Result -Name 'On-prem VM resolves Spoke1 storage via forwarding' -Success $onpremCanResolve1 -Message "Got: $onpremResolveSpoke1Str"
    
    # Test from Spoke1 VM
    Write-Host '  Testing from Spoke1 VM...' -ForegroundColor Gray
    $spoke1ResolveOwn = az vm run-command invoke `
        --resource-group $Spoke1ResourceGroupName `
        --name 'spoke1-vm-app' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke1Fqdn 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
        --query 'value[0].message' -o tsv 2>$null
    
    $spoke1ResolveOwnStr = if ($spoke1ResolveOwn) { [string]$spoke1ResolveOwn } else { '' }
    $spoke1CanResolveOwn = [bool]($spoke1ResolveOwnStr -match '10\.2\.')
    Test-Result -Name 'Spoke1 VM resolves own storage' -Success $spoke1CanResolveOwn -Message "Got: $spoke1ResolveOwnStr"
    
    $spoke1ResolveSpoke2 = az vm run-command invoke `
        --resource-group $Spoke1ResourceGroupName `
        --name 'spoke1-vm-app' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke2Fqdn 2>&1 | grep 'Address:' | tail -1 | awk '{print `$2}'" `
        --query 'value[0].message' -o tsv 2>$null
    
    $spoke1ResolveSpoke2Str = if ($spoke1ResolveSpoke2) { [string]$spoke1ResolveSpoke2 } else { '' }
    $spoke1CanResolve2 = [bool]($spoke1ResolveSpoke2Str -match '10\.3\.')
    Test-Result -Name 'Spoke1 VM resolves Spoke2 storage' -Success $spoke1CanResolve2 -Message "Got: $spoke1ResolveSpoke2Str"
}

# ================================================
# Cross-VNet Connectivity Tests
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Cross-VNet Connectivity' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host '  Testing Hub -> Spoke1 connectivity...' -ForegroundColor Gray
$hubToSpoke1Ping = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'ping -c 2 -W 2 10.2.10.4 && echo SUCCESS || echo FAIL' `
    --query 'value[0].message' -o tsv 2>$null

$hubToSpoke1Connected = [bool]($hubToSpoke1Ping -match 'SUCCESS')
Test-Result -Name 'Hub can ping Spoke1 VM (10.2.10.4)' -Success $hubToSpoke1Connected

Write-Host '  Testing Spoke1 -> Hub connectivity...' -ForegroundColor Gray
$spoke1ToHubPing = az vm run-command invoke `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-vm-app' `
    --command-id RunShellScript `
    --scripts 'ping -c 2 -W 2 10.1.10.4 && echo SUCCESS || echo FAIL' `
    --query 'value[0].message' -o tsv 2>$null

$spoke1ToHubConnected = [bool]($spoke1ToHubPing -match 'SUCCESS')
Test-Result -Name 'Spoke1 can ping Hub DNS (10.1.10.4)' -Success $spoke1ToHubConnected

# ================================================
# Summary
# ================================================
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host "Results: $script:passCount passed, $script:failCount failed" -ForegroundColor $(if ($script:failCount -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ''

if ($script:failCount -eq 0) {
    Write-Host '✓ Phase 7 validation complete!' -ForegroundColor Green
    Write-Host ''
    Write-Host 'All spoke networks configured with storage accounts and private endpoints.' -ForegroundColor Cyan
    Write-Host 'DNS resolution working via hub BIND9 server for privatelink zone.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Ready for Phase 8: Azure Private DNS + Resolver + Forwarding' -ForegroundColor Cyan
    Write-Host ''
    exit 0
}
else {
    Write-Host '⚠ Some tests failed. Review the output above.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
