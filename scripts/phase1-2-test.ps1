#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 1.2 DNS configuration.

.DESCRIPTION
Validates:
- VNet DNS servers point to the DNS VM
- BIND is running on the DNS VM
- onprem.pvt zone resolves from the client VM

.PARAMETER ResourceGroupName
Resource group name. Default: rg-onprem-dnsmig

.PARAMETER VnetName
VNet name. Default: onprem-vnet

.PARAMETER DnsVmName
DNS VM name. Default: onprem-vm-dns

.PARAMETER ClientVmName
Client VM name. Default: onprem-vm-client

.PARAMETER ZoneName
DNS zone to test. Default: onprem.pvt
#>

param(
    [string]$ResourceGroupName = 'rg-onprem-dnsmig',
    [string]$VnetName = 'onprem-vnet',
    [string]$DnsVmName = 'onprem-vm-dns',
    [string]$ClientVmName = 'onprem-vm-client',
    [string]$ZoneName = 'onprem.pvt'
)

$ErrorActionPreference = 'Stop'
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.2 Validation Tests - On-Prem DNS                 ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

function Test-Result {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message
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

Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'VNet DNS Configuration' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$dnsVmIp = az vm show -d --resource-group $ResourceGroupName --name $DnsVmName --query 'privateIps' -o tsv
$vnetDns = az network vnet show --resource-group $ResourceGroupName --name $VnetName --query 'dhcpOptions.dnsServers' -o json | ConvertFrom-Json

$dnsConfigured = $false
if ($vnetDns -and ($vnetDns -contains $dnsVmIp)) {
    $dnsConfigured = $true
}

Test-Result -Name "VNet DNS points to $DnsVmName" -Success $dnsConfigured -Message "Expected $dnsVmIp in VNet DNS servers"

Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'DNS VM Health' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$bindStatus = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts 'systemctl is-active bind9' `
    --query 'value[0].message' -o tsv

$bindActive = [bool]($bindStatus -match 'active')
Test-Result -Name 'bind9 service running' -Success $bindActive -Message "bind9 status: $bindStatus"

Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Client Resolution' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

$resolveOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $ClientVmName `
    --command-id RunShellScript `
    --scripts "dig +short dns.$ZoneName" `
    --query 'value[0].message' -o tsv

$resolved = [bool]($resolveOutput -match '\b\d{1,3}(\.\d{1,3}){3}\b')
Test-Result -Name "Resolve dns.$ZoneName" -Success $resolved -Message "No IP returned. Output: $resolveOutput"

Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Write-Host "Passed: $script:passCount" -ForegroundColor Green
Write-Host "Failed: $script:failCount" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($script:passCount + $script:failCount)" -ForegroundColor White
Write-Host ''

if ($script:failCount -gt 0) {
    exit 1
}

Write-Host 'All tests passed! ✓' -ForegroundColor Green
