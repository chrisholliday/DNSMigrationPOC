#!/usr/bin/env pwsh
<#
.SYNOPSIS
Phase 2: Establishes VNet peering between on-prem and hub environments.

.DESCRIPTION
Creates bidirectional VNet peering with the following settings:
- Allow virtual network access
- Allow forwarded traffic
- No gateway transit (not configured in Phase 1)

This enables network connectivity between the on-prem and hub VNets.

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremVnetName
On-prem VNet name. Default: onprem-vnet

.PARAMETER HubVnetName
Hub VNet name. Default: hub-vnet

.EXAMPLE
./phase2-deploy.ps1

.EXAMPLE
./phase2-deploy.ps1 -OnpremResourceGroupName "my-onprem-rg" -HubResourceGroupName "my-hub-rg"
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremVnetName = 'onprem-vnet',
    [string]$HubVnetName = 'hub-vnet'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 2 - VNet Peering                                    ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Validate resource groups exist
Write-Host '[1/4] Validating resource groups...' -ForegroundColor Yellow

$onpremExists = az group exists --name $OnpremResourceGroupName
if ($onpremExists -eq 'false') {
    Write-Error "On-prem resource group '$OnpremResourceGroupName' not found. Have you run Phase 1 deployment?"
}
Write-Host "✓ On-prem resource group found: $OnpremResourceGroupName" -ForegroundColor Green

$hubExists = az group exists --name $HubResourceGroupName
if ($hubExists -eq 'false') {
    Write-Error "Hub resource group '$HubResourceGroupName' not found. Have you run Phase 1 deployment?"
}
Write-Host "✓ Hub resource group found: $HubResourceGroupName" -ForegroundColor Green

# Get VNet IDs
Write-Host ''
Write-Host '[2/4] Getting VNet information...' -ForegroundColor Yellow

$onpremVnetId = az network vnet show `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremVnetName `
    --query 'id' -o tsv 2>$null

if (-not $onpremVnetId -or $LASTEXITCODE -ne 0) {
    Write-Error "Failed to get on-prem VNet ID. Ensure '$OnpremVnetName' exists in $OnpremResourceGroupName"
}
Write-Host "✓ On-prem VNet: $OnpremVnetName" -ForegroundColor Green
Write-Host "  ID: $onpremVnetId" -ForegroundColor Gray

$hubVnetId = az network vnet show `
    --resource-group $HubResourceGroupName `
    --name $HubVnetName `
    --query 'id' -o tsv 2>$null

if (-not $hubVnetId -or $LASTEXITCODE -ne 0) {
    Write-Error "Failed to get hub VNet ID. Ensure '$HubVnetName' exists in $HubResourceGroupName"
}
Write-Host "✓ Hub VNet: $HubVnetName" -ForegroundColor Green
Write-Host "  ID: $hubVnetId" -ForegroundColor Gray

# Create peering: Hub to On-Prem
Write-Host ''
Write-Host '[3/4] Creating peering: Hub → On-Prem...' -ForegroundColor Yellow

# Check if peering already exists
$existingHubPeering = az network vnet peering show `
    --resource-group $HubResourceGroupName `
    --vnet-name $HubVnetName `
    --name 'hub-to-onprem' 2>$null | ConvertFrom-Json

if ($existingHubPeering) {
    Write-Host "  ℹ Peering 'hub-to-onprem' already exists (state: $($existingHubPeering.peeringState))" -ForegroundColor Gray
    
    if ($existingHubPeering.peeringState -eq 'Connected') {
        Write-Host '  ✓ Peering is already connected' -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Peering exists but not connected (state: $($existingHubPeering.peeringState))" -ForegroundColor Yellow
    }
}
else {
    Write-Host '  Creating peering...' -ForegroundColor Gray
    az network vnet peering create `
        --resource-group $HubResourceGroupName `
        --name 'hub-to-onprem' `
        --vnet-name $HubVnetName `
        --remote-vnet $onpremVnetId `
        --allow-vnet-access `
        --allow-forwarded-traffic `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  ✓ Peering hub-to-onprem created successfully' -ForegroundColor Green
    }
    else {
        Write-Error 'Failed to create hub-to-onprem peering'
    }
}

# Create peering: On-Prem to Hub
Write-Host ''
Write-Host '[4/4] Creating peering: On-Prem → Hub...' -ForegroundColor Yellow

# Check if peering already exists
$existingOnpremPeering = az network vnet peering show `
    --resource-group $OnpremResourceGroupName `
    --vnet-name $OnpremVnetName `
    --name 'onprem-to-hub' 2>$null | ConvertFrom-Json

if ($existingOnpremPeering) {
    Write-Host "  ℹ Peering 'onprem-to-hub' already exists (state: $($existingOnpremPeering.peeringState))" -ForegroundColor Gray
    
    if ($existingOnpremPeering.peeringState -eq 'Connected') {
        Write-Host '  ✓ Peering is already connected' -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Peering exists but not connected (state: $($existingOnpremPeering.peeringState))" -ForegroundColor Yellow
    }
}
else {
    Write-Host '  Creating peering...' -ForegroundColor Gray
    az network vnet peering create `
        --resource-group $OnpremResourceGroupName `
        --name 'onprem-to-hub' `
        --vnet-name $OnpremVnetName `
        --remote-vnet $hubVnetId `
        --allow-vnet-access `
        --allow-forwarded-traffic `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  ✓ Peering onprem-to-hub created successfully' -ForegroundColor Green
    }
    else {
        Write-Error 'Failed to create onprem-to-hub peering'
    }
}

# Verify peering status
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Peering Status Verification' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$hubPeering = az network vnet peering show `
    --resource-group $HubResourceGroupName `
    --vnet-name $HubVnetName `
    --name 'hub-to-onprem' `
    --query '{name:name, state:peeringState, allowVnetAccess:allowVirtualNetworkAccess, allowForwarding:allowForwardedTraffic}' -o json | ConvertFrom-Json

Write-Host 'Hub → On-Prem:' -ForegroundColor White
Write-Host "  Name: $($hubPeering.name)" -ForegroundColor Gray
Write-Host "  State: $($hubPeering.state)" -ForegroundColor $(if ($hubPeering.state -eq 'Connected') { 'Green' } else { 'Yellow' })
Write-Host "  VNet Access: $($hubPeering.allowVnetAccess)" -ForegroundColor Gray
Write-Host "  Allow Forwarding: $($hubPeering.allowForwarding)" -ForegroundColor Gray

$onpremPeering = az network vnet peering show `
    --resource-group $OnpremResourceGroupName `
    --vnet-name $OnpremVnetName `
    --name 'onprem-to-hub' `
    --query '{name:name, state:peeringState, allowVnetAccess:allowVirtualNetworkAccess, allowForwarding:allowForwardedTraffic}' -o json | ConvertFrom-Json

Write-Host ''
Write-Host 'On-Prem → Hub:' -ForegroundColor White
Write-Host "  Name: $($onpremPeering.name)" -ForegroundColor Gray
Write-Host "  State: $($onpremPeering.state)" -ForegroundColor $(if ($onpremPeering.state -eq 'Connected') { 'Green' } else { 'Yellow' })
Write-Host "  VNet Access: $($onpremPeering.allowVnetAccess)" -ForegroundColor Gray
Write-Host "  Allow Forwarding: $($onpremPeering.allowForwarding)" -ForegroundColor Gray

Write-Host ''
if ($hubPeering.state -eq 'Connected' -and $onpremPeering.state -eq 'Connected') {
    Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host '✓ Phase 2 Complete: VNet Peering Established' -ForegroundColor Green
    Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Both peerings are connected and traffic can flow between VNets.' -ForegroundColor White
    Write-Host ''
    Write-Host 'Next Steps:' -ForegroundColor Cyan
    Write-Host '  1. Run validation tests:' -ForegroundColor White
    Write-Host '     ./scripts/phase2-test.ps1' -ForegroundColor Green
    Write-Host '  2. Proceed to Phase 3 to configure DNS services' -ForegroundColor White
    Write-Host ''
    exit 0
}
else {
    Write-Host '⚠ Warning: Peerings exist but may not be fully connected' -ForegroundColor Yellow
    Write-Host '  This can take a few moments. Check peering status:' -ForegroundColor Gray
    Write-Host "    Hub peering state: $($hubPeering.state)" -ForegroundColor Gray
    Write-Host "    On-prem peering state: $($onpremPeering.state)" -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Run the test script to verify:' -ForegroundColor White
    Write-Host '    ./scripts/phase2-test.ps1' -ForegroundColor Green
    exit 1
}
