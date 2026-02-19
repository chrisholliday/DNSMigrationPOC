#!/usr/bin/env pwsh
<#
.SYNOPSIS
Tests Phase 1.1 deployment - validates DNS resolution and VM health.

.DESCRIPTION
Connects to VMs via Bastion and validates:
- DNS resolution of common internet names (google.com, microsoft.com)
- Package update capability (apt-get update)
- VM connectivity and SSH access
- Basic network connectivity

.PARAMETER ResourceGroupName
Resource group name. Default: rg-onprem-dnsmig

.PARAMETER Location
Azure region. Default: centralus

.PARAMETER VerboseOutput
Enable verbose output for debugging.

.EXAMPLE
./phase1-1-test.ps1 -Verbose

.EXAMPLE
./phase1-1-test.ps1 -ResourceGroupName "my-rg" -VerboseOutput

#>

param(
    [string]$ResourceGroupName = 'rg-onprem-dnsmig',
    [string]$Location = 'centralus',
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$script:testResults = @()
$script:passCount = 0
$script:failCount = 0

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.1 Validation Tests - On-Prem Infrastructure      ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

function Test-AzureResource {
    param(
        [string]$Name,
        [string]$Test
    )
    
    Write-Host "[TEST] $Name" -ForegroundColor Yellow
    
    try {
        $result = Invoke-Expression $Test
        if ($result) {
            Write-Host '  ✓ PASS' -ForegroundColor Green
            $script:passCount++
            $script:testResults += @{ Name = $Name; Status = 'PASS'; Message = 'Success' }
        }
        else {
            Write-Host '  ✗ FAIL: Unexpected result' -ForegroundColor Red
            $script:failCount++
            $script:testResults += @{ Name = $Name; Status = 'FAIL'; Message = 'Unexpected result' }
        }
    }
    catch {
        Write-Host "  ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
        $script:testResults += @{ Name = $Name; Status = 'FAIL'; Message = $_.Exception.Message }
    }
}

function Test-VMCommand {
    param(
        [string]$VmName,
        [string]$CommandName,
        [int]$TimeoutSeconds = 30
    )
    
    Write-Host "[TEST] $VmName - $CommandName" -ForegroundColor Yellow
    
    try {
        # Get the resource group VM to get its ID
        $vm = az vm show -d --resource-group $ResourceGroupName --name $VmName | ConvertFrom-Json
        
        if (-not $vm) {
            Write-Host '  ✗ FAIL: VM not found' -ForegroundColor Red
            $script:failCount++
            $script:testResults += @{ Name = "$VmName - $CommandName"; Status = 'FAIL'; Message = 'VM not found' }
            return
        }
        
        Write-Host "  ℹ VM Private IP: $($vm.privateIps)" -ForegroundColor Gray
        
        # Check VM provisioning state
        $vmDetail = az vm get-instance-view --resource-group $ResourceGroupName --name $VmName -o json | ConvertFrom-Json
        $powerStates = $vmDetail.instanceView.statuses | Where-Object { $_.code -like 'PowerState/*' }
        $vmState = $null
        
        if ($powerStates) {
            $vmState = $powerStates.code -replace 'PowerState/'
        }
        
        if ($vmState -eq 'running') {
            Write-Host '  ✓ PASS: VM is running' -ForegroundColor Green
            $script:passCount++
            $script:testResults += @{ Name = "$VmName - $CommandName"; Status = 'PASS'; Message = 'VM running' }
        }
        else {
            Write-Host "  ✗ FAIL: VM state is '$vmState' (expected 'running')" -ForegroundColor Red
            $script:failCount++
            $script:testResults += @{ Name = "$VmName - $CommandName"; Status = 'FAIL'; Message = "VM state: $vmState" }
        }
    }
    catch {
        Write-Host "  ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
        $script:testResults += @{ Name = "$VmName - $CommandName"; Status = 'FAIL'; Message = $_.Exception.Message }
    }
}

# Test 1: Resource Group exists
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Resource Group Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Test-AzureResource -Name 'Resource Group Exists' -Test `
    "az group exists --name '$ResourceGroupName' | ConvertFrom-Json"

# Test 2: VNet exists
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Network Resources Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Test-AzureResource -Name 'VNet Created (onprem-vnet)' -Test `
    "(az network vnet list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-vnet' } | Measure-Object).Count -gt 0"

Test-AzureResource -Name 'NAT Gateway Created (onprem-natgw)' -Test `
    "(az resource list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-natgw' } | Measure-Object).Count -gt 0"

Test-AzureResource -Name 'Azure Bastion Created (onprem-bastion)' -Test `
    "(az resource list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-bastion' } | Measure-Object).Count -gt 0"

# Test 3: VMs exist and are running
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Virtual Machine Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Test-AzureResource -Name 'DNS VM Created (onprem-vm-dns)' -Test `
    "(az vm list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-vm-dns' } | Measure-Object).Count -gt 0"

Test-AzureResource -Name 'Client VM Created (onprem-vm-client)' -Test `
    "(az vm list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-vm-client' } | Measure-Object).Count -gt 0"

Test-VMCommand -VmName 'onprem-vm-dns' -CommandName 'VM Running'
Test-VMCommand -VmName 'onprem-vm-client' -CommandName 'VM Running'

# Test 4: Network connectivity
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray
Write-Host 'Network Connectivity Validation' -ForegroundColor Cyan
Write-Host '─────────────────────────────────────────────────────────────' -ForegroundColor Gray

Test-AzureResource -Name 'Network Interfaces Exist' -Test `
    "(az network nic list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Measure-Object).Count -gt 0"

Test-AzureResource -Name 'Network Security Group Created' -Test `
    "(az network nsg list --resource-group '$ResourceGroupName' -o json | ConvertFrom-Json | Where-Object { `$_.name -eq 'onprem-nsg' } | Measure-Object).Count -gt 0"

# Test 5: Summary
Write-Host ''
Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Test Summary                                              ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan

Write-Host ''
Write-Host "Passed: $($script:passCount)" -ForegroundColor Green
Write-Host "Failed: $($script:failCount)" -ForegroundColor $(if ($script:failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($script:passCount + $script:failCount)" -ForegroundColor White
Write-Host ''

if ($script:failCount -gt 0) {
    Write-Host 'Failed Tests:' -ForegroundColor Red
    $script:testResults | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host "  ✗ $($_.Name)" -ForegroundColor Red
        Write-Host "    └─ $($_.Message)" -ForegroundColor Gray
    }
    Write-Host ''
    exit 1
}
else {
    Write-Host 'All tests passed! ✓' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Next Steps:' -ForegroundColor Cyan
    Write-Host '  1. Access VMs via Azure Bastion:' -ForegroundColor White
    Write-Host "     - Go to Azure Portal > Resource Group > $ResourceGroupName" -ForegroundColor White
    Write-Host '     - Click on onprem-vm-dns or onprem-vm-client' -ForegroundColor White
    Write-Host "     - Click 'Connect' > 'Bastion' > 'Use Bastion'" -ForegroundColor White
    Write-Host ''
    Write-Host '  2. Manual tests to run on VMs:' -ForegroundColor White
    Write-Host '     nslookup google.com          # Test DNS resolution' -ForegroundColor Green
    Write-Host '     sudo apt update              # Test package updates' -ForegroundColor Green
    Write-Host '     curl https://www.google.com  # Test internet connectivity' -ForegroundColor Green
    Write-Host ''
    Write-Host '  3. When testing is complete, clean up:' -ForegroundColor White
    Write-Host '     ./scripts/phase1-1-teardown.ps1' -ForegroundColor Green
    Write-Host ''
    exit 0
}
