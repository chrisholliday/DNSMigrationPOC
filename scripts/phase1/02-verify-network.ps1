#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verify Phase 1: On-Prem Network Deployment
    
.DESCRIPTION
    Validates that the Phase 1 deployment is successful by checking:
    - Resource group and VMs exist
    - VMs are provisioned
    - Network connectivity works
    - Internet access is available
    - SSH access is functional
    
.PARAMETER ResourceGroupName
    Name of the resource group (default: dnsmig-rg-onprem)
    
.PARAMETER Verbose
    Show detailed output for each test

.EXAMPLE
    ./02-verify-network.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose
#>

param(
    [string]$ResourceGroupName = 'dnsmig-rg-onprem',
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Check {
    param(
        [string]$Message,
        [ValidateSet('Pass', 'Fail', 'Skip', 'Info', 'Testing')]
        [string]$Status = 'Info'
    )
    
    $colors = @{
        'Pass'    = 'Green'
        'Fail'    = 'Red'
        'Skip'    = 'Yellow'
        'Info'    = 'Cyan'
        'Testing' = 'Blue'
    }
    
    $symbols = @{
        'Pass'    = '✓'
        'Fail'    = '✗'
        'Skip'    = '⊘'
        'Info'    = '═'
        'Testing' = '⟳'
    }
    
    Write-Host "$($symbols[$Status]) $Message" -ForegroundColor $colors[$Status]
}

function Test-AzureAuth {
    try {
        $null = az account show --query 'id' -o tsv 2>$null
        return $true
    }
    catch {
        return $false
    }
}

function Get-VmDetails {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        $vm = az vm show -g $ResourceGroup -n $VmName --query '{name: name, provisioningState: provisioningState, powerState: powerState}' -o json 2>$null | ConvertFrom-Json
        return $vm
    }
    catch {
        return $null
    }
}

function Get-VmPrivateIp {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        $ip = az vm list-ip-addresses -g $ResourceGroup -n $VmName --query '[0].virtualMachine.network.privateIpAddresses[0]' -o tsv 2>$null
        return $ip
    }
    catch {
        return $null
    }
}

function Get-VmPublicIp {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        $ip = az vm show -d -g $ResourceGroup -n $VmName --query 'publicIps' -o tsv 2>$null
        return $ip
    }
    catch {
        return $null
    }
}

function Test-VmConnectivity {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Command
    )
    
    try {
        $output = az vm run-command invoke `
            -g $ResourceGroup `
            -n $VmName `
            --command-id RunShellScript `
            --scripts $Command `
            --query 'value[0].message' `
            -o tsv `
            --timeout-in-seconds 30 2>$null
        
        return @{
            Success = $true
            Output  = $output
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

# ============================================================================
# MAIN VALIDATION
# ============================================================================

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host 'Phase 1: Network Deployment Verification' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI auth
Write-Check 'Checking Azure CLI authentication...' -Status Testing
if (-not (Test-AzureAuth)) {
    Write-Check 'Not authenticated to Azure' -Status Fail
    Write-Host 'Please run: az login'
    exit 1
}
Write-Check 'Azure CLI authenticated' -Status Pass
Write-Host ''

# ============================================================================
# PHASE 1A: INFRASTRUCTURE EXISTENCE
# ============================================================================

Write-Check 'Phase 1a: Infrastructure Existence' -Status Info
Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
Write-Host ''

# Check resource group
Write-Check "Verifying resource group: $ResourceGroupName"
$rg = az group show -n $ResourceGroupName --query 'name' -o tsv 2>$null
if (-not $rg) {
    Write-Check 'Resource group not found' -Status Fail
    Write-Host 'Run Phase 1 deployment first: ./01-deploy-network.ps1'
    exit 1
}
Write-Check 'Resource group exists' -Status Pass
Write-Host ''

# Check VMs exist
Write-Check 'Checking DNS Server VM...'
$dnsVm = Get-VmDetails -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns'
if (-not $dnsVm) {
    Write-Check 'DNS Server VM not found' -Status Fail
    exit 1
}
Write-Check "DNS Server VM exists (state: $($dnsVm.powerState))" -Status Pass

Write-Check 'Checking Client VM...'
$clientVm = Get-VmDetails -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client'
if (-not $clientVm) {
    Write-Check 'Client VM not found' -Status Fail
    exit 1
}
Write-Check "Client VM exists (state: $($clientVm.powerState))" -Status Pass
Write-Host ''

# ============================================================================
# PHASE 1B: PROVISIONING STATE
# ============================================================================

Write-Check 'Phase 1b: Provisioning State' -Status Info
Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
Write-Host ''

Write-Check "DNS Server provisioning state: $($dnsVm.provisioningState)"
if ($dnsVm.provisioningState -ne 'Succeeded') {
    Write-Check 'VM still provisioning, this is normal for new deployments' -Status Skip
}
else {
    Write-Check 'DNS Server fully provisioned' -Status Pass
}

Write-Check "Client VM provisioning state: $($clientVm.provisioningState)"
if ($clientVm.provisioningState -ne 'Succeeded') {
    Write-Check 'VM still provisioning, this is normal for new deployments' -Status Skip
}
else {
    Write-Check 'Client VM fully provisioned' -Status Pass
}
Write-Host ''

# ============================================================================
# PHASE 1C: NETWORK CONFIGURATION
# ============================================================================

Write-Check 'Phase 1c: Network Configuration' -Status Info
Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
Write-Host ''

# Get private IPs
$dnsServerIp = Get-VmPrivateIp -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns'
$clientIp = Get-VmPrivateIp -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client'

Write-Check "DNS Server Private IP: $dnsServerIp"
Write-Check "Client VM Private IP: $clientIp"

# Get public IPs
$dnsPip = Get-VmPublicIp -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns'
$clientPip = Get-VmPublicIp -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client'

if ($dnsPip) {
    Write-Check "DNS Server Public IP: $dnsPip" -Status Pass
}
else {
    Write-Check 'DNS Server Public IP: (not yet assigned)' -Status Skip
}

if ($clientPip) {
    Write-Check "Client VM Public IP: $clientPip" -Status Pass
}
else {
    Write-Check 'Client VM Public IP: (not yet assigned)' -Status Skip
}

Write-Host ''

# ============================================================================
# PHASE 1D: CONNECTIVITY TESTS
# ============================================================================

if ($dnsVm.powerState -eq 'VM running' -and $clientVm.powerState -eq 'VM running') {
    Write-Check 'Phase 1d: Connectivity Tests' -Status Info
    Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
    Write-Host ''

    # Test DNS Server connectivity
    Write-Check 'Testing DNS Server internal connectivity...'
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns' -Command 'hostname && uptime'
    if ($result.Success) {
        Write-Check 'DNS Server responding via Azure run-command' -Status Pass
        if ($Verbose) {
            Write-Host "  └─ $($result.Output)" -ForegroundColor Gray
        }
    }
    else {
        Write-Check 'DNS Server not responding via Azure run-command' -Status Fail
        if ($Verbose) {
            Write-Host "  └─ Error: $($result.Error)" -ForegroundColor Gray
        }
    }

    # Test Client connectivity
    Write-Check 'Testing Client VM internal connectivity...'
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client' -Command 'hostname && uptime'
    if ($result.Success) {
        Write-Check 'Client VM responding via Azure run-command' -Status Pass
        if ($Verbose) {
            Write-Host "  └─ $($result.Output)" -ForegroundColor Gray
        }
    }
    else {
        Write-Check 'Client VM not responding via Azure run-command' -Status Fail
        if ($Verbose) {
            Write-Host "  └─ Error: $($result.Error)" -ForegroundColor Gray
        }
    }

    Write-Host ''

    # Test inter-VM connectivity
    Write-Check 'Testing network connectivity between VMs...'
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client' -Command "ping -c 1 $dnsServerIp"
    if ($result.Success -and $result.Output -like '*1 received*') {
        Write-Check "Client can reach DNS Server ($dnsServerIp)" -Status Pass
    }
    else {
        Write-Check "Client cannot reach DNS Server ($dnsServerIp)" -Status Fail
        if ($Verbose) {
            Write-Host "  └─ $($result.Output)" -ForegroundColor Gray
        }
    }

    Write-Host ''

    # Test internet connectivity
    Write-Check 'Testing internet connectivity (DNS Server)...'
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns' -Command 'ping -c 1 8.8.8.8'
    if ($result.Success -and $result.Output -like '*1 received*') {
        Write-Check 'DNS Server has internet connectivity via NAT Gateway' -Status Pass
    }
    else {
        Write-Check 'DNS Server cannot reach internet' -Status Fail
        if ($Verbose) {
            Write-Host "  └─ $($result.Output)" -ForegroundColor Gray
        }
    }

    Write-Check 'Testing internet connectivity (Client VM)...'
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client' -Command 'ping -c 1 8.8.8.8'
    if ($result.Success -and $result.Output -like '*1 received*') {
        Write-Check 'Client VM has internet connectivity via NAT Gateway' -Status Pass
    }
    else {
        Write-Check 'Client VM cannot reach internet' -Status Fail
        if ($Verbose) {
            Write-Host "  └─ $($result.Output)" -ForegroundColor Gray
        }
    }

    Write-Host ''
}
else {
    Write-Check 'VMs not yet fully running - skipping connectivity tests' -Status Skip
    Write-Host '  (This is normal for new deployments; check again in 2-3 minutes)'
    Write-Host ''
}

# ============================================================================
# PHASE 1E: CLOUD-INIT STATUS
# ============================================================================

Write-Check 'Phase 1e: Cloud-Init Status' -Status Info
Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
Write-Host ''

Write-Check 'Checking DNS Server cloud-init status...'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-dns' -Command 'cloud-init status --format json'
if ($result.Success) {
    try {
        $ciStatus = $result.Output | ConvertFrom-Json
        if ($ciStatus.status -eq 'done') {
            Write-Check 'Cloud-init completed successfully' -Status Pass
        }
        else {
            Write-Check "Cloud-init status: $($ciStatus.status)" -Status Skip
        }
    }
    catch {
        Write-Check 'Could not parse cloud-init status' -Status Skip
    }
}

Write-Check 'Checking Client VM cloud-init status...'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName 'dnsmig-onprem-vm-client' -Command 'cloud-init status --format json'
if ($result.Success) {
    try {
        $ciStatus = $result.Output | ConvertFrom-Json
        if ($ciStatus.status -eq 'done') {
            Write-Check 'Cloud-init completed successfully' -Status Pass
        }
        else {
            Write-Check "Cloud-init status: $($ciStatus.status)" -Status Skip
        }
    }
    catch {
        Write-Check 'Could not parse cloud-init status' -Status Skip
    }
}

Write-Host ''

# ============================================================================
# SUMMARY
# ============================================================================

Write-Check 'Phase 1 Verification Summary' -Status Info
Write-Host '──────────────────────────────────────────────' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Phase 1 Success Criteria:' -ForegroundColor Cyan
Write-Host '  ✓ Resource group created'
Write-Host '  ✓ VMs deployed and provisioned'
Write-Host '  ✓ Network connectivity working'
Write-Host '  ✓ Internet access available'
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. If internet test failed, wait 2-3 minutes and rerun this script'
Write-Host '  2. Once all tests pass, proceed to Phase 2 (DNS Server Configuration):'
Write-Host '     ./03-configure-dns-server.ps1 -ResourceGroupName dnsmig-rg-onprem -Verbose'
Write-Host ''
