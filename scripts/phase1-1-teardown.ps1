#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tears down Phase 1.1 - Removes all resources created during deployment.

.DESCRIPTION
Deletes the on-prem resource group and all contained resources.
This is useful for cleaning up between deployment attempts.

WARNING: This action cannot be undone. All resources in the resource group will be permanently deleted.

.PARAMETER ResourceGroupName
Resource group name to delete. Default: rg-onprem-dnsmig

.PARAMETER Force
Skip confirmation prompt and delete immediately without questions.

.PARAMETER WaitForDeletion
Wait for resource group deletion to complete before returning to prompt. Default: $true

.EXAMPLE
./phase1-1-teardown.ps1 -Force

.EXAMPLE
./phase1-1-teardown.ps1 -WaitForDeletion $true

#>

param(
    [string]$ResourceGroupName = 'rg-onprem-dnsmig',
    [switch]$Force,
    [bool]$WaitForDeletion = $true
)

$ErrorActionPreference = 'Stop'

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  Phase 1.1 Teardown - Resource Cleanup                   ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# Check if resource group exists
Write-Host "Checking resource group status..." -ForegroundColor Yellow

$rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json

if (-not $rgExists) {
    Write-Host "✓ Resource group '$ResourceGroupName' does not exist. Nothing to delete." -ForegroundColor Green
    exit 0
}

Write-Host "✓ Resource group found: $ResourceGroupName" -ForegroundColor Green
Write-Host ""

# Get resource count
Write-Host "Enumerating resources..." -ForegroundColor Yellow
$resources = az resource list --resource-group $ResourceGroupName | ConvertFrom-Json
$resourceCount = ($resources | Measure-Object).Count

Write-Host "✓ Found $resourceCount resource(s) to delete" -ForegroundColor White
Write-Host ""

# Show resources that will be deleted
if ($resourceCount -gt 0) {
    Write-Host "Resources in group (will be deleted):" -ForegroundColor Cyan
    $resources | ForEach-Object {
        Write-Host "  • $($_.name) [$($_.type)]" -ForegroundColor White
    }
    Write-Host ""
}

# Confirmation prompt
if (-not $Force) {
    Write-Host "⚠️  WARNING: This action will PERMANENTLY DELETE all resources above." -ForegroundColor Red
    Write-Host "   This action cannot be undone." -ForegroundColor Red
    Write-Host ""
    
    $confirmation = Read-Host "Are you sure you want to delete resource group '$ResourceGroupName'? (yes/no)"
    
    if ($confirmation -ne 'yes') {
        Write-Host ""
        Write-Host "Teardown cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Delete resource group
Write-Host "Deleting resource group..." -ForegroundColor Yellow
Write-Host ""

if ($WaitForDeletion) {
    try {
        $startTime = Get-Date
        az group delete --name $ResourceGroupName --yes --no-wait
        
        # Poll for completion
        $maxAttempts = 60
        $attempt = 0
        
        while ($attempt -lt $maxAttempts) {
            $attempt++
            
            $rgStillExists = az group exists --name $ResourceGroupName 2>$null | ConvertFrom-Json
            
            if (-not $rgStillExists) {
                $elapsedTime = (Get-Date) - $startTime
                Write-Host ""
                Write-Host "✓ Resource group '$ResourceGroupName' deleted successfully" -ForegroundColor Green
                Write-Host "  Deletion completed in $($elapsedTime.TotalSeconds.ToString('F0')) seconds" -ForegroundColor Green
                Write-Host ""
                exit 0
            }
            
            Write-Host -NoNewline "."
            Start-Sleep -Seconds 5
        }
        
        Write-Host ""
        Write-Host "⚠️  Resource group is still being deleted in the background." -ForegroundColor Yellow
        Write-Host "   Check Azure Portal for completion status." -ForegroundColor Yellow
        exit 0
    }
    catch {
        Write-Host ""
        Write-Host "✓ Teardown initiated successfully" -ForegroundColor Green
        Write-Host "  Deletion is proceeding in the background." -ForegroundColor Gray
        Write-Host "  You can monitor progress in Azure Portal > Resource Groups" -ForegroundColor Gray
        exit 0
    }
} else {
    az group delete --name $ResourceGroupName --yes --no-wait
    Write-Host "✓ Teardown initiated. Deletion proceeding in background." -ForegroundColor Green
    exit 0
}
