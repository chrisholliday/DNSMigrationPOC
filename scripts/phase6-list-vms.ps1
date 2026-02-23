#!/usr/bin/env pwsh
<#
.SYNOPSIS
List all VMs and their status in the hub resource group.
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Hub Resource Group VM Inventory                          ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Host "Resource Group: $HubResourceGroupName" -ForegroundColor Cyan
Write-Host ''

# Check if resource group exists
Write-Host '[1] Checking resource group...' -ForegroundColor Yellow
$rgCheck = az group exists --name $HubResourceGroupName 2>&1
Write-Host "  Exists: $rgCheck" -ForegroundColor $(if ($rgCheck -eq 'true') { 'Green' } else { 'Red' })

if ($rgCheck -ne 'true') {
    Write-Error "Resource group '$HubResourceGroupName' not found!"
}

Write-Host ''
Write-Host '[2] Listing all VMs...' -ForegroundColor Yellow

try {
    $vms = az vm list --resource-group $HubResourceGroupName 2>&1 | ConvertFrom-Json
    
    if ($vms.Count -eq 0) {
        Write-Host '  No VMs found in resource group!' -ForegroundColor Red
        exit 1
    }
    
    foreach ($vm in $vms) {
        Write-Host ''
        Write-Host "  VM: $($vm.name)" -ForegroundColor White
        Write-Host "    Location: $($vm.location)" -ForegroundColor Gray
        Write-Host "    VM Size: $($vm.hardwareProfile.vmSize)" -ForegroundColor Gray
        Write-Host "    Provisioning State: $($vm.provisioningState)" -ForegroundColor Gray
        
        # Get detailed status
        Write-Host '    Getting power state...' -ForegroundColor Gray
        $vmDetails = az vm show --ids $vm.id --show-details 2>&1 | ConvertFrom-Json
        Write-Host "    Power State: $($vmDetails.powerState)" -ForegroundColor $(if ($vmDetails.powerState -eq 'VM running') { 'Green' } else { 'Yellow' })
    }
}
catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ''
    Write-Host 'Raw output:' -ForegroundColor Yellow
    $rawOutput = az vm list --resource-group $HubResourceGroupName 2>&1
    Write-Host $rawOutput -ForegroundColor Gray
}

Write-Host ''
Write-Host '[3] Checking hub-vm-app specifically...' -ForegroundColor Yellow

try {
    $clientVm = az vm show --resource-group $HubResourceGroupName --name 'hub-vm-app' 2>&1 | ConvertFrom-Json
    
    Write-Host '  ✓ hub-vm-app found' -ForegroundColor Green
    Write-Host "    ID: $($clientVm.id)" -ForegroundColor Gray
    
    # Get instance view
    Write-Host ''
    Write-Host '  Getting instance view...' -ForegroundColor Gray
    $instanceView = az vm get-instance-view --ids $clientVm.id 2>&1 | ConvertFrom-Json
    
    Write-Host "  VM Agent Status: $($instanceView.vmAgent.statuses[0].displayStatus)" -ForegroundColor Cyan
    Write-Host "  VM Agent Version: $($instanceView.vmAgent.vmAgentVersion)" -ForegroundColor Gray
    
    if ($instanceView.vmAgent.statuses[0].displayStatus -ne 'Ready') {
        Write-Host '  ⚠ VM Agent is not ready! This explains why run-command is failing.' -ForegroundColor Yellow
    }
}
catch {
    Write-Host '  ✗ hub-vm-app not found or error accessing it' -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host '[4] Testing simple run-command on hub-vm-app...' -ForegroundColor Yellow

try {
    Write-Host '  Running: echo "TEST"...' -ForegroundColor Gray
    $testResult = az vm run-command invoke `
        --resource-group $HubResourceGroupName `
        --name 'hub-vm-app' `
        --command-id RunShellScript `
        --scripts 'echo "TEST_OUTPUT"' 2>&1
    
    Write-Host '  Raw result:' -ForegroundColor Gray
    Write-Host $testResult -ForegroundColor DarkGray
    
    # Try to parse
    $parsed = $testResult | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($parsed) {
        Write-Host ''
        Write-Host "  Parsed message: $($parsed.value[0].message)" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "  ✗ Run-command failed: $_" -ForegroundColor Red
}

Write-Host ''

exit 0
