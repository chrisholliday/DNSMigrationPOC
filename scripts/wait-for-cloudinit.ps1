#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Wait for cloud-init to complete on Azure VMs.
    
.DESCRIPTION
    Polls the specified VMs until cloud-init has completed by checking for the boot-finished marker.
    Provides visual feedback on progress and elapsed time.
    
.PARAMETER ResourceGroupName
    Name of the resource group
    
.PARAMETER VmNames
    Names of the VMs to wait for (comma-separated)
    
.PARAMETER MaxWaitSeconds
    Maximum time to wait before timeout (default: 600 = 10 minutes)
    
.PARAMETER PollIntervalSeconds
    How often to check status in seconds (default: 10)

.EXAMPLE
    ./wait-for-cloudinit.ps1 -ResourceGroupName dnsmig-rg-onprem -VmNames dnsmig-onprem-vm-dns,dnsmig-onprem-vm-client
    
.EXAMPLE
    # With custom wait times (check every 5 seconds, max 120 seconds)
    ./wait-for-cloudinit.ps1 -ResourceGroupName dnsmig-rg-onprem -VmNames "dns-vm,client-vm" -PollIntervalSeconds 5 -MaxWaitSeconds 120
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$VmNames,
    
    [int]$MaxWaitSeconds = 600,
    [int]$PollIntervalSeconds = 10
)

$ErrorActionPreference = 'Continue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Progress')]
        [string]$Type = 'Info'
    )
    
    $colors = @{
        'Info'     = 'Cyan'
        'Success'  = 'Green'
        'Warning'  = 'Yellow'
        'Error'    = 'Red'
        'Progress' = 'Blue'
    }
    
    Write-Host "$Message" -ForegroundColor $colors[$Type]
}

function Test-CloudInitComplete {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        # Check if cloud-init boot-finished marker exists
        # This file is created when cloud-init completes (even if there are warnings)
        $cmd = 'test -f /var/lib/cloud/instance/boot-finished && echo "yes" || echo "no"'
        $result = az vm run-command invoke `
            -g $ResourceGroup `
            -n $VmName `
            --command-id RunShellScript `
            --scripts $cmd `
            --query 'value[0].message' `
            -o tsv `
            --timeout-in-seconds 10 2>$null
        
        return ($result -like '*yes*')
    }
    catch {
        return $false
    }
}

function Get-CloudInitStatus {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        # Get cloud-init status if available
        $cmd = 'cloud-init status --format json 2>/dev/null || echo "{\"status\":\"unknown\"}"'
        $result = az vm run-command invoke `
            -g $ResourceGroup `
            -n $VmName `
            --command-id RunShellScript `
            --scripts $cmd `
            --query 'value[0].message' `
            -o tsv `
            --timeout-in-seconds 10 2>$null
        
        try {
            $status = $result | ConvertFrom-Json
            return @{
                Status  = $status.status
                Running = $status.running
            }
        }
        catch {
            return @{
                Status  = 'unknown'
                Running = 'unknown'
            }
        }
    }
    catch {
        return @{
            Status  = 'error'
            Running = 'unknown'
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host ''
Write-Status '═══════════════════════════════════════════════════════════════' -Type Progress
Write-Status 'Waiting for Cloud-Init Completion' -Type Progress
Write-Status '═══════════════════════════════════════════════════════════════' -Type Progress
Write-Host ''

$vms = $VmNames -split ',' | ForEach-Object { $_.Trim() }
Write-Host "Monitoring $($vms.Count) VM(s):" -ForegroundColor Cyan
$vms | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
Write-Host ''

$startTime = Get-Date
$allComplete = $false
$pollCount = 0
$maxPolls = [math]::Ceiling($MaxWaitSeconds / $PollIntervalSeconds)

while (-not $allComplete -and ((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitSeconds) {
    $pollCount++
    $elapsedSeconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
    
    Write-Host "[$elapsedSeconds/$MaxWaitSeconds seconds] Poll #$pollCount..." -ForegroundColor Gray
    
    $allComplete = $true
    $statusSummary = @()
    
    foreach ($vm in $vms) {
        $isComplete = Test-CloudInitComplete -ResourceGroup $ResourceGroupName -VmName $vm
        
        if ($isComplete) {
            Write-Status "  ✓ $vm - cloud-init completed" -Type Success
            $statusSummary += "${vm}: ✓"
        }
        else {
            Write-Status "  ⟳ $vm - still initializing..." -Type Progress
            $allComplete = $false
            $statusSummary += "${vm}: ⟳"
        }
    }
    
    if (-not $allComplete) {
        Write-Host "  Waiting $PollIntervalSeconds seconds before next check..." -ForegroundColor Gray
        Start-Sleep -Seconds $PollIntervalSeconds
        Write-Host ''
    }
}

Write-Host ''
Write-Status '═══════════════════════════════════════════════════════════════' -Type Progress

if ($allComplete) {
    Write-Status '✓ All VMs ready! Cloud-init completed successfully.' -Type Success
    Write-Host "  Total wait time: $([math]::Round(((Get-Date) - $startTime).TotalSeconds)) seconds"
    Write-Host ''
    exit 0
}
else {
    Write-Status '✗ Timeout waiting for cloud-init completion.' -Type Error
    Write-Host ''
    Write-Host 'This may indicate:' -ForegroundColor Yellow
    Write-Host '  • VMs are still initializing (try running again)'
    Write-Host '  • Package installation issues during cloud-init'
    Write-Host '  • Network connectivity problems'
    Write-Host ''
    Write-Host 'Check cloud-init logs for more details:' -ForegroundColor Yellow
    foreach ($vm in $vms) {
        Write-Host "  az vm run-command invoke -g $ResourceGroupName -n $vm --command-id RunShellScript --scripts 'tail -100 /var/log/cloud-init-output.log'" -ForegroundColor Gray
    }
    Write-Host ''
    exit 1
}
