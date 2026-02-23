#!/usr/bin/env pwsh
<#
.SYNOPSIS
Diagnose hub-vm-app VM status and connectivity.

.DESCRIPTION
Checks if the VM is running and responding to commands.
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Hub VM Client Diagnostics                                ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Host '[1] Checking VM power state...' -ForegroundColor Yellow
$vmState = az vm show `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --show-details `
    --query '[name, powerState, provisioningState]' -o tsv 2>$null

Write-Host "  VM State: $vmState" -ForegroundColor $(if ($vmState -match 'VM running') { 'Green' } else { 'Red' })

if ($vmState -notmatch 'VM running') {
    Write-Host ''
    Write-Host '  VM is not running! Starting VM...' -ForegroundColor Yellow
    az vm start --resource-group $HubResourceGroupName --name 'hub-vm-app' --no-wait
    Write-Host '  Waiting for VM to start (60 seconds)...' -ForegroundColor Gray
    Start-Sleep -Seconds 60
}

Write-Host ''
Write-Host '[2] Testing run-command capability...' -ForegroundColor Yellow
$echoTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'echo "TEST_SUCCESS"' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host "  Run-command result: $echoTest" -ForegroundColor $(if ($echoTest -match 'TEST_SUCCESS') { 'Green' } else { 'Red' })

Write-Host ''
Write-Host '[3] Checking VM guest agent...' -ForegroundColor Yellow
$agentStatus = az vm get-instance-view `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --query 'instanceView.vmAgent.statuses[0].[code, displayStatus]' -o tsv 2>$null

Write-Host "  Agent status: $agentStatus" -ForegroundColor Cyan

Write-Host ''
Write-Host '[4] Checking network interface...' -ForegroundColor Yellow
$nicTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'ip addr show eth0 | grep "inet " | awk "{print \$2}"' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host "  IP address: $nicTest" -ForegroundColor Cyan

Write-Host ''
Write-Host '[5] Checking DNS resolution capability...' -ForegroundColor Yellow
$dnsTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'resolvectl status 2>&1 | head -20' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host '  Resolvectl output:' -ForegroundColor Cyan
Write-Host $dnsTest -ForegroundColor Gray

Write-Host ''
Write-Host '[6] Manual restart of hub-vm-app...' -ForegroundColor Yellow
Write-Host '  Restarting VM...' -ForegroundColor Gray
az vm restart --resource-group $HubResourceGroupName --name 'hub-vm-app' --no-wait

Write-Host '  Waiting for restart (90 seconds)...' -ForegroundColor Gray
Start-Sleep -Seconds 90

Write-Host ''
Write-Host '  Checking VM state after restart...' -ForegroundColor Gray
$vmStateAfter = az vm show `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --show-details `
    --query 'powerState' -o tsv 2>$null

Write-Host "  Power state: $vmStateAfter" -ForegroundColor $(if ($vmStateAfter -match 'VM running') { 'Green' } else { 'Red' })

Write-Host ''
Write-Host '  Testing DNS after restart...' -ForegroundColor Gray
Start-Sleep -Seconds 10

$dnsTestAfter = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'resolvectl status | grep "DNS Servers" | head -1' `
    --query 'value[0].message' -o tsv 2>$null

Write-Host "  DNS config: $dnsTestAfter" -ForegroundColor Cyan

if ($dnsTestAfter -match '10\.1\.10\.4') {
    Write-Host ''
    Write-Host '✓ VM is now configured correctly!' -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host '⚠ VM may still have issues. Check Azure Portal for guest agent status.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next step: Wait 1 minute, then run ./scripts/phase6-test.ps1' -ForegroundColor Cyan
Write-Host ''

exit 0
