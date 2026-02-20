#!/usr/bin/env pwsh
<#
.SYNOPSIS
Phase 4: Switch On-Prem VNet to use custom DNS server.

.DESCRIPTION
Activates the custom DNS server configured in Phase 3:
- Updates On-Prem VNet DNS settings to point to onprem-vm-dns (10.0.10.4)
- Restarts VMs to acquire new DNS settings via DHCP
- Validates VMs are using the custom DNS server

This is the "cutover" that activates custom DNS for the on-prem environment.

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER OnpremVnetName
On-prem VNet name. Default: onprem-vnet

.PARAMETER DnsServerIp
DNS server IP address. Default: 10.0.10.4

.EXAMPLE
./phase4-deploy.ps1

.EXAMPLE
./phase4-deploy.ps1 -OnpremResourceGroupName "my-onprem-rg"
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$OnpremVnetName = 'onprem-vnet',
    [string]$DnsServerIp = '10.0.10.4'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 4 - On-Prem DNS Cutover                            ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''
Write-Host '⚠  WARNING: This will change DNS settings for all on-prem VMs' -ForegroundColor Yellow
Write-Host '   VMs will be restarted to acquire new DNS configuration' -ForegroundColor Yellow
Write-Host ''

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Validate resource group and VNet exist
Write-Host '[1/4] Validating environment...' -ForegroundColor Yellow

$rgExists = az group exists --name $OnpremResourceGroupName
if ($rgExists -eq 'false') {
    Write-Error "Resource group '$OnpremResourceGroupName' not found. Have you run Phase 1?"
}
Write-Host "✓ Resource group found: $OnpremResourceGroupName" -ForegroundColor Green

$vnet = az network vnet show --resource-group $OnpremResourceGroupName --name $OnpremVnetName 2>$null | ConvertFrom-Json
if (-not $vnet) {
    Write-Error "VNet '$OnpremVnetName' not found in $OnpremResourceGroupName"
}
Write-Host "✓ VNet found: $OnpremVnetName" -ForegroundColor Green

# Check current DNS settings
$currentDns = $vnet.dhcpOptions.dnsServers
if ($currentDns -and $currentDns.Count -gt 0) {
    Write-Host "  Current DNS servers: $($currentDns -join ', ')" -ForegroundColor Gray
    if ($currentDns -contains $DnsServerIp) {
        Write-Host "  ℹ VNet already configured with $DnsServerIp" -ForegroundColor Cyan
    }
}
else {
    Write-Host '  Current DNS: Azure DNS (168.63.129.16)' -ForegroundColor Gray
}

# Verify DNS server is accessible
Write-Host ''
Write-Host '[2/4] Verifying DNS server is running...' -ForegroundColor Yellow

$dnsCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts 'systemctl is-active named 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

if (-not ($dnsCheck -match 'active')) {
    Write-Host "  DNS service status: $dnsCheck" -ForegroundColor Red
    Write-Error 'DNS server (onprem-vm-dns) is not running. Run Phase 3 first.'
}

Write-Host "✓ DNS server is running on $DnsServerIp" -ForegroundColor Green

# Update VNet DNS settings
Write-Host ''
Write-Host '[3/4] Updating VNet DNS settings...' -ForegroundColor Yellow
Write-Host "  Setting DNS server to: $DnsServerIp" -ForegroundColor Gray

az network vnet update `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremVnetName `
    --dns-servers $DnsServerIp `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to update VNet DNS settings'
}

Write-Host "✓ VNet DNS updated to $DnsServerIp" -ForegroundColor Green

# Restart VMs to acquire new DNS settings
Write-Host ''
Write-Host '[4/4] Restarting VMs to acquire new DNS settings...' -ForegroundColor Yellow
Write-Host '  This will take 2-3 minutes...' -ForegroundColor Gray

# Get all VMs in the resource group
$vms = az vm list --resource-group $OnpremResourceGroupName --query '[].name' -o tsv

if (-not $vms) {
    Write-Error 'No VMs found in resource group'
}

$vmArray = $vms -split "`n" | Where-Object { $_ }

foreach ($vmName in $vmArray) {
    Write-Host "  Restarting $vmName..." -ForegroundColor Cyan
    
    # Use restart (faster than deallocate/start)
    az vm restart `
        --resource-group $OnpremResourceGroupName `
        --name $vmName `
        --no-wait `
        --output none
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠ Warning: Failed to restart $vmName" -ForegroundColor Yellow
    }
}

# Wait for all VMs to complete restart
Write-Host ''
Write-Host '  Waiting for VMs to restart...' -ForegroundColor Gray
Start-Sleep -Seconds 5

# Check VM states
$allRunning = $false
$attempts = 0
$maxAttempts = 60

while (-not $allRunning -and $attempts -lt $maxAttempts) {
    $attempts++
    $vmStates = @()
    
    foreach ($vmName in $vmArray) {
        $vmState = az vm show `
            --resource-group $OnpremResourceGroupName `
            --name $vmName `
            --show-details `
            --query 'powerState' -o tsv 2>$null
        
        $vmStates += $vmState
    }
    
    if ($vmStates -notcontains 'VM running' -or $vmStates.Count -ne $vmArray.Count) {
        Write-Host "  Attempt $attempts/$maxAttempts - Waiting for VMs..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
    else {
        $allRunning = $true
    }
}

if (-not $allRunning) {
    Write-Host '  ⚠ Warning: Some VMs may still be restarting' -ForegroundColor Yellow
}
else {
    Write-Host '  ✓ All VMs are running' -ForegroundColor Green
}

# Give VMs time to acquire DHCP settings
Write-Host '  Waiting for DHCP configuration...' -ForegroundColor Gray
Start-Sleep -Seconds 10

# Verify DNS configuration on client VM
Write-Host ''
Write-Host '  Verifying DNS configuration on client VM...' -ForegroundColor Cyan

$resolvConfCheck = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'resolvectl status | grep "DNS Servers" | head -1' `
    --query 'value[0].message' -o tsv 2>$null

if ($resolvConfCheck -match $DnsServerIp) {
    Write-Host "  ✓ Client VM is using DNS server $DnsServerIp" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ DNS configuration: $resolvConfCheck" -ForegroundColor Yellow
    Write-Host '    You may need to wait a few more minutes for DHCP to propagate' -ForegroundColor Gray
}

# Summary
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host '✓ Phase 4 Complete: On-Prem DNS Cutover' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'DNS Cutover Details:' -ForegroundColor Cyan
Write-Host "  VNet: $OnpremVnetName" -ForegroundColor White
Write-Host "  DNS Server: $DnsServerIp (onprem-vm-dns)" -ForegroundColor White
Write-Host '  VMs: Restarted to acquire new DNS settings' -ForegroundColor White
Write-Host ''
Write-Host 'Important Notes:' -ForegroundColor Yellow
Write-Host '  • VMs now use custom DNS server for all resolution' -ForegroundColor White
Write-Host '  • onprem.pvt zone is now resolvable from all on-prem VMs' -ForegroundColor White
Write-Host '  • Internet names forwarded to Azure DNS (168.63.129.16)' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Run validation tests:' -ForegroundColor White
Write-Host '     ./scripts/phase4-test.ps1' -ForegroundColor Green
Write-Host '  2. Verify onprem.pvt resolution from client VM' -ForegroundColor White
Write-Host '  3. Proceed to Phase 5 for Hub DNS configuration' -ForegroundColor White
Write-Host ''

exit 0
