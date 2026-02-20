#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 2 VNet peering deployment.

.DESCRIPTION
Validates:
- VNet peering exists in both directions
- Peering status is "Connected"
- Network connectivity between VMs across peered VNets
- Internet connectivity still works

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.EXAMPLE
./phase2-test.ps1
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubResourceGroupName = 'rg-hub-dnsmig'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 2 Validation Tests - VNet Peering                  ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ''
    )

    Write-Host "[TEST] $Name" -ForegroundColor Yellow

    if ($Success) {
        Write-Host '  ✓ PASS' -ForegroundColor Green
        $script:passCount++
    }
    else {
        Write-Host "  ✗ FAIL: $Message" -ForegroundColor Red
        $script:failCount++
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

Write-Host 'Configuration:' -ForegroundColor Cyan
Write-Host "  On-prem RG: $OnpremResourceGroupName" -ForegroundColor White
Write-Host "  Hub RG:     $HubResourceGroupName" -ForegroundColor White
Write-Host ''

# ================================================
# VNet Peering
# ================================================
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet Peering Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Hub to On-prem peering
$hubPeering = az network vnet peering show `
    --resource-group $HubResourceGroupName `
    --vnet-name 'hub-vnet' `
    --name 'hub-to-onprem' 2>$null | ConvertFrom-Json

Test-Result -Name 'Hub-to-OnPrem peering exists' -Success ($null -ne $hubPeering) -Message 'Peering not found'

if ($hubPeering) {
    $hubPeeringConnected = $hubPeering.peeringState -eq 'Connected'
    Test-Result -Name 'Hub-to-OnPrem peering is Connected' -Success $hubPeeringConnected -Message "Peering state: $($hubPeering.peeringState)"
    
    $hubAllowVnetAccess = $hubPeering.allowVirtualNetworkAccess -eq $true
    Test-Result -Name 'Hub-to-OnPrem allows VNet access' -Success $hubAllowVnetAccess -Message 'VNet access not enabled'
    
    $hubAllowForwarding = $hubPeering.allowForwardedTraffic -eq $true
    Test-Result -Name 'Hub-to-OnPrem allows forwarded traffic' -Success $hubAllowForwarding -Message 'Forwarded traffic not enabled'
}

# On-prem to Hub peering
$onpremPeering = az network vnet peering show `
    --resource-group $OnpremResourceGroupName `
    --vnet-name 'onprem-vnet' `
    --name 'onprem-to-hub' 2>$null | ConvertFrom-Json

Test-Result -Name 'OnPrem-to-Hub peering exists' -Success ($null -ne $onpremPeering) -Message 'Peering not found'

if ($onpremPeering) {
    $onpremPeeringConnected = $onpremPeering.peeringState -eq 'Connected'
    Test-Result -Name 'OnPrem-to-Hub peering is Connected' -Success $onpremPeeringConnected -Message "Peering state: $($onpremPeering.peeringState)"
    
    $onpremAllowVnetAccess = $onpremPeering.allowVirtualNetworkAccess -eq $true
    Test-Result -Name 'OnPrem-to-Hub allows VNet access' -Success $onpremAllowVnetAccess -Message 'VNet access not enabled'
    
    $onpremAllowForwarding = $onpremPeering.allowForwardedTraffic -eq $true
    Test-Result -Name 'OnPrem-to-Hub allows forwarded traffic' -Success $onpremAllowForwarding -Message 'Forwarded traffic not enabled'
}

# ================================================
# Cross-VNet Connectivity
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Cross-VNet Network Connectivity' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Test: On-prem Client VM can ping Hub DNS VM (10.1.10.4)
Write-Host '  Testing: OnPrem Client → Hub DNS (10.1.10.4)...' -ForegroundColor Gray
$onpremToHubPing = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'ping -c 3 -W 2 10.1.10.4 > /dev/null 2>&1 && echo "success" || echo "failed"' `
    --query 'value[0].message' -o tsv 2>$null

$onpremToHubPingOk = [bool]($onpremToHubPing -match 'success')
Test-Result -Name 'OnPrem Client can ping Hub DNS VM (10.1.10.4)' -Success $onpremToHubPingOk -Message "Ping result: $onpremToHubPing"

# Test: On-prem Client VM can ping Hub App VM (10.1.10.5)
Write-Host '  Testing: OnPrem Client → Hub App (10.1.10.5)...' -ForegroundColor Gray
$onpremToHubAppPing = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'ping -c 3 -W 2 10.1.10.5 > /dev/null 2>&1 && echo "success" || echo "failed"' `
    --query 'value[0].message' -o tsv 2>$null

$onpremToHubAppPingOk = [bool]($onpremToHubAppPing -match 'success')
Test-Result -Name 'OnPrem Client can ping Hub App VM (10.1.10.5)' -Success $onpremToHubAppPingOk -Message "Ping result: $onpremToHubAppPing"

# Test: Hub App VM can ping On-prem DNS VM (10.0.10.4)
Write-Host '  Testing: Hub App → OnPrem DNS (10.0.10.4)...' -ForegroundColor Gray
$hubToOnpremPing = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'ping -c 3 -W 2 10.0.10.4 > /dev/null 2>&1 && echo "success" || echo "failed"' `
    --query 'value[0].message' -o tsv 2>$null

$hubToOnpremPingOk = [bool]($hubToOnpremPing -match 'success')
Test-Result -Name 'Hub App can ping OnPrem DNS VM (10.0.10.4)' -Success $hubToOnpremPingOk -Message "Ping result: $hubToOnpremPing"

# Test: Hub App VM can ping On-prem Client VM (10.0.10.5)
Write-Host '  Testing: Hub App → OnPrem Client (10.0.10.5)...' -ForegroundColor Gray
$hubToOnpremClientPing = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'ping -c 3 -W 2 10.0.10.5 > /dev/null 2>&1 && echo "success" || echo "failed"' `
    --query 'value[0].message' -o tsv 2>$null

$hubToOnpremClientPingOk = [bool]($hubToOnpremClientPing -match 'success')
Test-Result -Name 'Hub App can ping OnPrem Client VM (10.0.10.5)' -Success $hubToOnpremClientPingOk -Message "Ping result: $hubToOnpremClientPing"

# ================================================
# Internet Connectivity (verify still works)
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Internet Connectivity (Post-Peering)' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

# Quick test on one VM from each side
Write-Host '  Testing: OnPrem Client → Internet...' -ForegroundColor Gray
$onpremInternet = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-client' `
    --command-id RunShellScript `
    --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 10 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$onpremInternetOk = [bool]($onpremInternet -match '200')
Test-Result -Name 'OnPrem Client still has internet access' -Success $onpremInternetOk -Message "HTTP response: $onpremInternet"

Write-Host '  Testing: Hub App → Internet...' -ForegroundColor Gray
$hubInternet = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-app' `
    --command-id RunShellScript `
    --scripts 'curl -s -o /dev/null -w "%{http_code}" https://www.microsoft.com --max-time 10 2>&1' `
    --query 'value[0].message' -o tsv 2>$null

$hubInternetOk = [bool]($hubInternet -match '200')
Test-Result -Name 'Hub App still has internet access' -Success $hubInternetOk -Message "HTTP response: $hubInternet"

# ================================================
# Summary
# ================================================
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host "Passed: $script:passCount" -ForegroundColor Green
Write-Host "Failed: $script:failCount" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($script:passCount + $script:failCount)" -ForegroundColor White
Write-Host ''

if ($script:failCount -gt 0) {
    Write-Host 'Some tests failed. Review the output above for details.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Common issues:' -ForegroundColor Yellow
    Write-Host '  - Peering may still be initializing (wait 1-2 minutes)' -ForegroundColor White
    Write-Host '  - NSG rules may be blocking traffic (check Azure Portal)' -ForegroundColor White
    Write-Host '  - VMs may need DHCP refresh for routing updates' -ForegroundColor White
    exit 1
}

Write-Host '✓ All tests passed! VNet peering is working correctly.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  Phase 2 is complete. The on-prem and hub VNets can now communicate.' -ForegroundColor White
Write-Host ''
Write-Host '  Ready for Phase 3: Configure DNS services' -ForegroundColor White
Write-Host '    - Install and configure BIND9 on DNS VMs' -ForegroundColor Gray
Write-Host '    - Set up DNS forwarding' -ForegroundColor Gray
Write-Host '    - Configure conditional forwarding for Azure DNS' -ForegroundColor Gray
Write-Host ''

exit 0
