#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Diagnose Phase 7 DNS configuration
.DESCRIPTION
    Checks DNS configuration on hub-vm-dns and VM DNS settings
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$Spoke1ResourceGroupName = 'rg-spoke1-dnsmig',
    [string]$Spoke2ResourceGroupName = 'rg-spoke2-dnsmig'
)

$ErrorActionPreference = 'Stop'

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 7 DNS Diagnostics' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ================================================
# Check Hub DNS Server Configuration
# ================================================
Write-Host '─── Hub DNS Server (hub-vm-dns) ───' -ForegroundColor Yellow
Write-Host ''

Write-Host '1. Checking named.conf.local...' -ForegroundColor Cyan
$namedConf = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'cat /etc/bind/named.conf.local' `
    --query 'value[0].message' -o tsv 2>$null

if ($namedConf -match 'blob\.core\.windows\.net') {
    Write-Host '  ✓ blob.core.windows.net zone configured' -ForegroundColor Green
}
else {
    Write-Host '  ✗ blob.core.windows.net zone NOT configured' -ForegroundColor Red
}

if ($namedConf -match 'privatelink\.blob\.core\.windows\.net') {
    Write-Host '  ✓ privatelink.blob.core.windows.net zone configured' -ForegroundColor Green
}
else {
    Write-Host '  ✗ privatelink.blob.core.windows.net zone NOT configured' -ForegroundColor Red
}
Write-Host ''

Write-Host '2. Checking zone files exist...' -ForegroundColor Cyan
$zoneFiles = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'ls -lh /etc/bind/db.*.blob.core.windows.net 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host $zoneFiles -ForegroundColor Gray
Write-Host ''

Write-Host '3. Checking blob.core.windows.net zone content...' -ForegroundColor Cyan
$blobZone = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'cat /etc/bind/db.blob.core.windows.net 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host $blobZone -ForegroundColor Gray
Write-Host ''

Write-Host '4. Checking privatelink.blob.core.windows.net zone content...' -ForegroundColor Cyan
$privatelinkZone = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'cat /etc/bind/db.privatelink.blob.core.windows.net 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host $privatelinkZone -ForegroundColor Gray
Write-Host ''

Write-Host '5. Checking BIND9 status...' -ForegroundColor Cyan
$bindStatus = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl status bind9 --no-pager | head -15' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host $bindStatus -ForegroundColor Gray
Write-Host ''

# ================================================
# Check VM DNS Settings
# ================================================
Write-Host '─── VM DNS Configuration ───' -ForegroundColor Yellow
Write-Host ''

Write-Host '1. Checking Spoke1 VNet DNS servers...' -ForegroundColor Cyan
$spoke1VnetDns = az network vnet list `
    --resource-group $Spoke1ResourceGroupName `
    --query '[0].dhcpOptions.dnsServers' -o json 2>$null | ConvertFrom-Json

if ($spoke1VnetDns -contains '10.1.10.4') {
    Write-Host '  ✓ Spoke1 VNet configured to use 10.1.10.4' -ForegroundColor Green
}
else {
    Write-Host "  ✗ Spoke1 VNet DNS servers: $($spoke1VnetDns -join ', ')" -ForegroundColor Red
}
Write-Host ''

Write-Host '2. Checking Spoke2 VNet DNS servers...' -ForegroundColor Cyan
$spoke2VnetDns = az network vnet list `
    --resource-group $Spoke2ResourceGroupName `
    --query '[0].dhcpOptions.dnsServers' -o json 2>$null | ConvertFrom-Json

if ($spoke2VnetDns -contains '10.1.10.4') {
    Write-Host '  ✓ Spoke2 VNet configured to use 10.1.10.4' -ForegroundColor Green
}
else {
    Write-Host "  ✗ Spoke2 VNet DNS servers: $($spoke2VnetDns -join ', ')" -ForegroundColor Red
}
Write-Host ''

Write-Host '3. Checking actual DNS resolver on Spoke1 VM...' -ForegroundColor Cyan
$spoke1VmDns = az vm run-command invoke `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-vm-app' `
    --command-id RunShellScript `
    --scripts 'cat /etc/resolv.conf' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host $spoke1VmDns -ForegroundColor Gray
Write-Host ''

# ================================================
# Test DNS Resolution Directly
# ================================================
Write-Host '─── Direct DNS Resolution Tests ───' -ForegroundColor Yellow
Write-Host ''

# Get storage account names
$spoke1Storage = az storage account list `
    --resource-group $Spoke1ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

$spoke2Storage = az storage account list `
    --resource-group $Spoke2ResourceGroupName `
    --query '[0].name' -o tsv 2>$null

if ($spoke1Storage) {
    Write-Host "Testing: $spoke1Storage.blob.core.windows.net" -ForegroundColor Cyan
    
    Write-Host '  Query from hub-vm-dns (dig):' -ForegroundColor Gray
    $digResult = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name 'hub-vm-dns' `
        --command-id RunShellScript `
        --scripts "dig +short $spoke1Storage.blob.core.windows.net @127.0.0.1" `
        --query 'value[0].message' -o tsv 2>$null
    
    Write-Host "    Result: $digResult" -ForegroundColor White
    Write-Host ''
    
    Write-Host '  Query from spoke1-vm-app (nslookup):' -ForegroundColor Gray
    $nslookupResult = az vm run-command invoke `
        --resource-group $Spoke1ResourceGroupName `
        --name 'spoke1-vm-app' `
        --command-id RunShellScript `
        --scripts "nslookup $spoke1Storage.blob.core.windows.net" `
        --query 'value[0].message' -o tsv 2>$null
    
    Write-Host $nslookupResult -ForegroundColor White
    Write-Host ''
}

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Diagnostics Complete' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
