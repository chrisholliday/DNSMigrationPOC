#!/usr/bin/env pwsh
<#
.SYNOPSIS
Force DHCP renewal on Hub VMs to acquire new DNS settings.

.DESCRIPTION
Sometimes VMs don't immediately pick up new VNet DNS settings after a restart.
This script forces DHCP renewal and restarts systemd-resolved.

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.EXAMPLE
./scripts/phase6-force-dhcp-renewal.ps1
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Force DHCP Renewal on Hub VMs                            ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Get all VMs in the hub resource group
$vms = az vm list --resource-group $HubResourceGroupName --query '[].name' -o tsv

if (-not $vms) {
    Write-Error 'No VMs found in resource group'
}

$vmArray = $vms -split "`n" | Where-Object { $_ }

foreach ($vmName in $vmArray) {
    Write-Host "Processing $vmName..." -ForegroundColor Cyan
    
    $renewScript = @'
#!/bin/bash
set -x

echo "Current DNS configuration:"
resolvectl status | grep "DNS Servers" | head -1

echo ""
echo "Releasing DHCP lease..."
sudo dhclient -r 2>&1 || true

echo "Restarting network interface..."
sudo ip link set eth0 down
sudo ip link set eth0 up

echo "Requesting new DHCP lease..."
sudo dhclient eth0 2>&1 || true

echo "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

sleep 3

echo ""
echo "New DNS configuration:"
resolvectl status | grep "DNS Servers" | head -1

echo ""
echo "Testing DNS resolution:"
nslookup dns.azure.pvt 2>&1 | grep -A 1 "Address:" || echo "DNS resolution test query"
'@

    Write-Host '  Running DHCP renewal...' -ForegroundColor Gray
    $output = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name $vmName `
        --command-id RunShellScript `
        --scripts $renewScript `
        --query 'value[0].message' -o tsv 2>$null
    
    Write-Host '  Output:' -ForegroundColor Gray
    Write-Host $output -ForegroundColor DarkGray
    
    if ($output -match '10\.1\.10\.4') {
        Write-Host "  ✓ $vmName now using custom DNS (10.1.10.4)" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ $vmName may need manual intervention" -ForegroundColor Yellow
    }
    
    Write-Host ''
}

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'DHCP renewal complete. Wait 30 seconds, then run:' -ForegroundColor Cyan
Write-Host '  ./scripts/phase6-test.ps1' -ForegroundColor Green
Write-Host ''

exit 0
