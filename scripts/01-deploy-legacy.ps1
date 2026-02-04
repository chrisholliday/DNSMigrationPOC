param(
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig',
    [string]$AdminUsername = 'azureuser',
    [Parameter(Mandatory = $true)][string]$SshPublicKeyPath
)

$root = Split-Path -Parent $PSScriptRoot
$sshPublicKey = Get-Content -Path $SshPublicKeyPath -Raw

$rgName = "$Prefix-rg"

Write-Host '=================================================='
Write-Host 'Phase 1: Create Networking Infrastructure'
Write-Host '=================================================='

# Create resource group
Write-Host "Creating resource group: $rgName..."
New-AzResourceGroup -Name $rgName -Location $Location -Force | Out-Null

# Phase 1: Deploy VNets, Subnets, NSGs
Write-Host 'Deploying VNets and subnets...'
$bicepFile = Join-Path $root 'bicep\01-networking.bicep'
$deployParams = @{
    ResourceGroupName       = $rgName
    TemplateFile            = $bicepFile
    TemplateParameterObject = @{
        location = $Location
    }
}

$phase1 = New-AzResourceGroupDeployment @deployParams
if (-not $phase1.ProvisioningState -eq 'Succeeded') {
    Write-Error "Phase 1 deployment failed: $($phase1.ProvisioningState)"
    exit 1
}

Write-Host '✓ Phase 1 Complete: VNets and subnets deployed'
Write-Host ''

# Validation 1: Check all VNets exist
Write-Host 'Validating VNets...'
$expectedVnets = 'dnsmig-onprem-vnet', 'dnsmig-hub-vnet', 'dnsmig-spoke1-vnet', 'dnsmig-spoke2-vnet'
foreach ($vnet in $expectedVnets) {
    $v = Get-AzVirtualNetwork -ResourceGroupName $rgName -Name $vnet -ErrorAction SilentlyContinue
    if ($v) {
        Write-Host "  ✓ $vnet exists"
    }
    else {
        Write-Error "  ✗ $vnet NOT FOUND"
        exit 1
    }
}

Write-Host ''
Write-Host '=================================================='
Write-Host 'Phase 2: Create VNet Peerings'
Write-Host '=================================================='

# Phase 2: Deploy Peerings
Write-Host 'Creating VNet peerings...'
$bicepFile = Join-Path $root 'bicep\02-peering.bicep'
$deployParams = @{
    ResourceGroupName = $rgName
    TemplateFile      = $bicepFile

}

$phase2 = New-AzResourceGroupDeployment @deployParams
if (-not $phase2.ProvisioningState -eq 'Succeeded') {
    Write-Error "Phase 2 deployment failed: $($phase2.ProvisioningState)"
    exit 1
}

Write-Host '✓ Phase 2 Complete: VNet peerings created'
Write-Host ''

# Validation 2: Check all peerings are active
Write-Host 'Validating peerings...'
$expectedPeerings = @(
    @{ vnet = 'dnsmig-onprem-vnet'; peering = 'dnsmig-onprem-to-hub' }
    @{ vnet = 'dnsmig-hub-vnet'; peering = 'dnsmig-hub-to-onprem' }
    @{ vnet = 'dnsmig-hub-vnet'; peering = 'dnsmig-hub-to-spoke1' }
    @{ vnet = 'dnsmig-spoke1-vnet'; peering = 'dnsmig-spoke1-to-hub' }
    @{ vnet = 'dnsmig-hub-vnet'; peering = 'dnsmig-hub-to-spoke2' }
    @{ vnet = 'dnsmig-spoke2-vnet'; peering = 'dnsmig-spoke2-to-hub' }
)

foreach ($peer in $expectedPeerings) {
    $p = Get-AzVirtualNetworkPeering -ResourceGroupName $rgName -VirtualNetworkName $peer.vnet -Name $peer.peering -ErrorAction SilentlyContinue
    if ($p -and $p.PeeringState -eq 'Connected') {
        Write-Host "  ✓ $($peer.vnet) -> $($peer.peering) is Connected"
    }
    else {
        Write-Host "  ! $($peer.vnet) -> $($peer.peering) state: $($p.PeeringState)"
    }
}

Write-Host ''
Write-Host '=================================================='
Write-Host 'Phase 3: Deploy Virtual Machines'
Write-Host '=================================================='

# Phase 3: Deploy VMs
Write-Host 'Deploying VMs and cloud-init scripts...'
$bicepFile = Join-Path $root 'bicep\03-vms.bicep'
$deployParams = @{
    ResourceGroupName       = $rgName
    TemplateFile            = $bicepFile
    TemplateParameterObject = @{
        location      = $Location
        adminUsername = $AdminUsername
        sshPublicKey  = $sshPublicKey
    }
}

$phase3 = New-AzResourceGroupDeployment @deployParams
if (-not $phase3.ProvisioningState -eq 'Succeeded') {
    Write-Error "Phase 3 deployment failed: $($phase3.ProvisioningState)"
    exit 1
}

Write-Host '✓ Phase 3 Complete: VMs deployed'
Write-Host ''

# Validation 3: Check all VMs exist and provisioned
Write-Host 'Validating VMs...'
$expectedVms = 'dnsmig-onprem-dns', 'dnsmig-onprem-client', 'dnsmig-hub-dns', 'dnsmig-spoke1-app', 'dnsmig-spoke2-app'
foreach ($vmName in $expectedVms) {
    $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName -ErrorAction SilentlyContinue
    if ($vm -and $vm.ProvisioningState -eq 'Succeeded') {
        Write-Host "  ✓ $vmName provisioned successfully"
    }
    elseif ($vm) {
        Write-Host "  ! $vmName state: $($vm.ProvisioningState)"
    }
    else {
        Write-Error "  ✗ $vmName NOT FOUND"
        exit 1
    }
}

Write-Host ''
Write-Host '=================================================='
Write-Host '✓ Legacy Environment Deployment Complete!'
Write-Host '=================================================='
Write-Host ''
Write-Host 'All VNets, peerings, and VMs have been deployed.'
Write-Host ''
Write-Host "Resource Group: $rgName"
Write-Host "Location: $Location"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Verify DNS resolution with: ./scripts/validate.ps1 -Phase Legacy'
Write-Host '  2. Deploy Private DNS with: ./scripts/02-deploy-private-dns.ps1'
