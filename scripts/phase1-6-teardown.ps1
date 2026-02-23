#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Teardown Phase 1-6: Remove all infrastructure deployed by phase1-6-deploy.ps1

.DESCRIPTION
Deletes the on-prem and hub resource groups and all contained resources.
This is useful for cleaning up between deployment attempts.

WARNING: This action cannot be undone. All resources will be permanently deleted.

.PARAMETER Force
Skip confirmation prompt and delete immediately without questions.

.PARAMETER WaitForDeletion
Wait for resource group deletion to complete before returning. Default: $false

.EXAMPLE
./phase1-6-teardown.ps1 -Force

.EXAMPLE
./phase1-6-teardown.ps1 -WaitForDeletion $true

#>

param(
    [switch]$Force,
    [bool]$WaitForDeletion = $false
)

$ErrorActionPreference = 'Stop'

$OnpremResourceGroupName = 'rg-onprem-dnsmig'
$HubResourceGroupName = 'rg-hub-dnsmig'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║  Phase 1-6 Teardown - Full Infrastructure Cleanup         ║' -ForegroundColor Magenta
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host ''

# Check which resource groups exist
Write-Host 'Checking resource groups...' -ForegroundColor Yellow

$onpremExists = az group exists --name $OnpremResourceGroupName | ConvertFrom-Json
$hubExists = az group exists --name $HubResourceGroupName | ConvertFrom-Json

if (-not $onpremExists -and -not $hubExists) {
    Write-Host '✓ No resource groups found. Nothing to delete.' -ForegroundColor Green
    exit 0
}

$groupsToDelete = @()
if ($onpremExists) { $groupsToDelete += $OnpremResourceGroupName }
if ($hubExists) { $groupsToDelete += $HubResourceGroupName }

Write-Host "Found $($groupsToDelete.Count) resource group(s) to delete:" -ForegroundColor White
$groupsToDelete | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }
Write-Host ''

# Get resource counts
$totalResources = 0
foreach ($rg in $groupsToDelete) {
    $resources = az resource list --resource-group $rg | ConvertFrom-Json
    $count = ($resources | Measure-Object).Count
    $totalResources += $count
    
    Write-Host "$rg ($count resources):" -ForegroundColor Cyan
    $resources | Select-Object -First 10 | ForEach-Object {
        Write-Host "  • $($_.name) [$($_.type)]" -ForegroundColor Gray
    }
    if ($count -gt 10) {
        Write-Host "  ... and $($count - 10) more" -ForegroundColor Gray
    }
    Write-Host ''
}

# Confirmation
if (-not $Force) {
    Write-Host "⚠️  WARNING: This will PERMANENTLY DELETE $totalResources resource(s) in $($groupsToDelete.Count) resource group(s)." -ForegroundColor Red
    Write-Host '   This action cannot be undone.' -ForegroundColor Red
    Write-Host ''
    
    $confirmation = Read-Host 'Type "DELETE" to confirm deletion'
    
    if ($confirmation -ne 'DELETE') {
        Write-Host ''
        Write-Host 'Teardown cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

# Delete resource groups
Write-Host ''
Write-Host 'Deleting resource groups...' -ForegroundColor Yellow
Write-Host ''

$startTime = Get-Date

foreach ($rg in $groupsToDelete) {
    Write-Host "  Deleting $rg..." -ForegroundColor Yellow
    
    if ($WaitForDeletion) {
        az group delete --name $rg --yes --output none
        Write-Host "  ✓ $rg deleted" -ForegroundColor Green
    }
    else {
        az group delete --name $rg --yes --no-wait --output none
        Write-Host "  → $rg deletion started" -ForegroundColor Cyan
    }
}

if ($WaitForDeletion) {
    $elapsedTime = (Get-Date) - $startTime
    Write-Host ''
    Write-Host "✓ All resource groups deleted ($($elapsedTime.Minutes)m $($elapsedTime.Seconds)s)" -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host '✓ Deletion requests submitted' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Resource groups are being deleted in the background.' -ForegroundColor Cyan
    Write-Host 'This typically takes 5-10 minutes.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Check status with:' -ForegroundColor Yellow
    foreach ($rg in $groupsToDelete) {
        Write-Host "  az group exists --name $rg" -ForegroundColor White
    }
}

Write-Host ''
exit 0
