param(
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig',
    [string]$AdminUsername = 'azureuser',
    [Parameter(Mandatory = $true)][string]$SshPublicKeyPath,
    [string]$OnpremRg,
    [string]$HubRg,
    [string]$Spoke1Rg,
    [string]$Spoke2Rg
)

$root = Split-Path -Parent $PSScriptRoot

# Check if user is logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host 'You are not logged in to Azure. Connecting now...'
    Connect-AzAccount
    $context = Get-AzContext
    if (-not $context) {
        Write-Error 'Failed to connect to Azure'
        exit 1
    }
}

Write-Host "Connected to Azure subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
Write-Host ''

# Check if bicep is installed
try {
    $bicepVersion = bicep --version 2>$null
    Write-Host "Bicep is installed: $bicepVersion"
}
catch {
    Write-Error 'Bicep CLI is not installed or not in PATH. Please install bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install'
    exit 1
}

Write-Host ''

if (-not (Test-Path $SshPublicKeyPath)) {
    Write-Error "SSH public key file not found: $SshPublicKeyPath"
    exit 1
}

$sshPublicKey = Get-Content -Path $SshPublicKeyPath -Raw

if (-not $sshPublicKey) {
    Write-Error "SSH public key file is empty: $SshPublicKeyPath"
    exit 1
}

if (-not $OnpremRg) { $OnpremRg = "$Prefix-rg-onprem" }
if (-not $HubRg) { $HubRg = "$Prefix-rg-hub" }
if (-not $Spoke1Rg) { $Spoke1Rg = "$Prefix-rg-spoke1" }
if (-not $Spoke2Rg) { $Spoke2Rg = "$Prefix-rg-spoke2" }

$rgNames = @{
    onprem = $OnpremRg
    hub    = $HubRg
    spoke1 = $Spoke1Rg
    spoke2 = $Spoke2Rg
}

Write-Host '=================================================='
Write-Host 'Phase 1: Create Resource Groups'
Write-Host '=================================================='

foreach ($rg in $rgNames.Values) {
    Write-Host "Creating resource group: $rg..."
    New-AzResourceGroup -Name $rg -Location $Location -Force | Out-Null
}

Write-Host ''
Write-Host '=================================================='
Write-Host 'Phase 2: Deploy Networking'
Write-Host '=================================================='

Write-Host 'Deploying VNets and peerings...'
$networkingBicepFile = Join-Path $root 'bicep\01-networking.bicep'
$networkingParams = @{
    Location     = $Location
    TemplateFile = $networkingBicepFile
}

# Deploy networking with retry logic
$maxRetries = 5
$retryCount = 0
$deployment = $null
$retryDelaySeconds = 60

do {
    $retryCount++
    try {
        # Deploy to each resource group
        foreach ($rgName in @($OnpremRg, $HubRg, $Spoke1Rg, $Spoke2Rg)) {
            Write-Host "  Deploying networking to $rgName..."
            $deployment = New-AzResourceGroupDeployment @networkingParams -ResourceGroupName $rgName -ErrorAction Stop
            if ($deployment.ProvisioningState -ne 'Succeeded') {
                Write-Error "Deployment to $rgName failed: $($deployment.ProvisioningState)"
                exit 1
            }
        }
        break
    }
    catch {
        $errorMessage = $_.Exception.Message
        if (($errorMessage -match 'AnotherOperationInProgress' -or $errorMessage -match 'InUseSubnetCannotBeDeleted') -and $retryCount -lt $maxRetries) {
            Write-Host "  ⚠ Transient Azure operation conflict. Retrying in $retryDelaySeconds seconds (attempt $retryCount/$maxRetries)..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
        else {
            Write-Error "Deployment failed: $errorMessage"
            exit 1
        }
    }
} while ($null -eq $deployment -and $retryCount -lt $maxRetries)

if ($null -eq $deployment) {
    Write-Error "Deployment failed after $maxRetries attempts"
    exit 1
}

Write-Host '✓ Phase 2 Complete: Networking deployed'
Write-Host ''
Write-Host '=================================================='
Write-Host 'Phase 2b: Deploy Peerings'
Write-Host '=================================================='

Write-Host 'Deploying VNet peerings...'
$peeringBicepFile = Join-Path $root 'bicep\02-peering.bicep'
$peeringParams = @{
    Location     = $Location
    TemplateFile = $peeringBicepFile
}

$retryCount = 0
$deployment = $null

do {
    $retryCount++
    try {
        # Deploy peerings to each resource group where they are defined
        foreach ($rgEntry in @(
                @{ rg = $OnpremRg; name = 'onprem' }
                @{ rg = $HubRg; name = 'hub' }
                @{ rg = $Spoke1Rg; name = 'spoke1' }
                @{ rg = $Spoke2Rg; name = 'spoke2' }
            )) {
            Write-Host "  Deploying peerings from $($rgEntry.rg)..."
            $deployment = New-AzResourceGroupDeployment @peeringParams -ResourceGroupName $rgEntry.rg -ErrorAction Stop
            if ($deployment.ProvisioningState -ne 'Succeeded') {
                Write-Host "  ! Peering deployment to $($rgEntry.rg) state: $($deployment.ProvisioningState)"
            }
        }
        break
    }
    catch {
        $errorMessage = $_.Exception.Message
        if (($errorMessage -match 'AnotherOperationInProgress' -or $errorMessage -match 'InUseSubnetCannotBeDeleted') -and $retryCount -lt $maxRetries) {
            Write-Host "  ⚠ Transient Azure operation conflict. Retrying in $retryDelaySeconds seconds (attempt $retryCount/$maxRetries)..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
        else {
            Write-Host "  ! Peering deployment warning: $errorMessage"
        }
    }
} while ($retryCount -lt 1)

Write-Host '✓ Phase 2b Complete: Peerings deployed'
Write-Host ''
Write-Host '=================================================='
Write-Host 'Phase 3: Deploy VMs'
Write-Host '=================================================='

Write-Host 'Deploying VMs...'
$vmsBicepFile = Join-Path $root 'bicep\03-vms.bicep'
$vmsParams = @{
    Location                = $Location
    TemplateFile            = $vmsBicepFile
    TemplateParameterObject = @{
        adminUsername = $AdminUsername
        sshPublicKey  = $sshPublicKey
    }
}

$retryCount = 0
$deployment = $null

do {
    $retryCount++
    try {
        # Deploy VMs to each resource group
        foreach ($rgEntry in @(
                @{ rg = $OnpremRg; name = 'onprem' }
                @{ rg = $HubRg; name = 'hub' }
                @{ rg = $Spoke1Rg; name = 'spoke1' }
                @{ rg = $Spoke2Rg; name = 'spoke2' }
            )) {
            Write-Host "  Deploying VMs to $($rgEntry.rg)..."
            $deployment = New-AzResourceGroupDeployment @vmsParams -ResourceGroupName $rgEntry.rg -ErrorAction Stop
            if ($deployment.ProvisioningState -ne 'Succeeded') {
                Write-Error "VM deployment to $($rgEntry.rg) failed: $($deployment.ProvisioningState)"
                exit 1
            }
        }
        break
    }
    catch {
        $errorMessage = $_.Exception.Message
        if (($errorMessage -match 'AnotherOperationInProgress' -or $errorMessage -match 'InUseSubnetCannotBeDeleted') -and $retryCount -lt $maxRetries) {
            Write-Host "  ⚠ Transient Azure operation conflict. Retrying in $retryDelaySeconds seconds (attempt $retryCount/$maxRetries)..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
        else {
            Write-Error "VM Deployment failed: $errorMessage"
            exit 1
        }
    }
} while ($null -eq $deployment -and $retryCount -lt $maxRetries)

if ($null -eq $deployment) {
    Write-Error "VM Deployment failed after $maxRetries attempts"
    exit 1
}

Write-Host '✓ Phase 3 Complete: VMs deployed'
Write-Host ''

# Validation 1: Check all VNets exist
Write-Host 'Validating VNets...'
$expectedVnets = @(
    @{ rg = $OnpremRg; vnet = "$Prefix-onprem-vnet" }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet" }
    @{ rg = $Spoke1Rg; vnet = "$Prefix-spoke1-vnet" }
    @{ rg = $Spoke2Rg; vnet = "$Prefix-spoke2-vnet" }
)

foreach ($entry in $expectedVnets) {
    $v = Get-AzVirtualNetwork -ResourceGroupName $entry.rg -Name $entry.vnet -ErrorAction SilentlyContinue
    if ($v) {
        Write-Host "  ✓ $($entry.vnet) exists in $($entry.rg)"
    }
    else {
        Write-Error "  ✗ $($entry.vnet) NOT FOUND in $($entry.rg)"
        exit 1
    }
}

# Validation 2: Check all peerings are active
Write-Host 'Validating peerings...'
$expectedPeerings = @(
    @{ rg = $OnpremRg; vnet = "$Prefix-onprem-vnet"; peering = 'dnsmig-onprem-to-hub' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'dnsmig-hub-to-onprem' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'dnsmig-hub-to-spoke1' }
    @{ rg = $Spoke1Rg; vnet = "$Prefix-spoke1-vnet"; peering = 'dnsmig-spoke1-to-hub' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'dnsmig-hub-to-spoke2' }
    @{ rg = $Spoke2Rg; vnet = "$Prefix-spoke2-vnet"; peering = 'dnsmig-spoke2-to-hub' }
)

foreach ($peer in $expectedPeerings) {
    $p = Get-AzVirtualNetworkPeering -ResourceGroupName $peer.rg -VirtualNetworkName $peer.vnet -Name $peer.peering -ErrorAction SilentlyContinue
    if ($p -and $p.PeeringState -eq 'Connected') {
        Write-Host "  ✓ $($peer.vnet) -> $($peer.peering) is Connected"
    }
    elseif ($p) {
        Write-Host "  ! $($peer.vnet) -> $($peer.peering) state: $($p.PeeringState) (may still be connecting)"
    }
    else {
        Write-Host "  ! $($peer.vnet) -> $($peer.peering) not yet available"
    }
}

Write-Host ''

# Validation 3: Check all VMs exist and provisioned
Write-Host 'Validating VMs...'
$expectedVms = @(
    @{ rg = $OnpremRg; vm = "$Prefix-onprem-vm-dns" }
    @{ rg = $OnpremRg; vm = "$Prefix-onprem-vm-client" }
    @{ rg = $HubRg; vm = "$Prefix-hub-vm-dns" }
    @{ rg = $Spoke1Rg; vm = "$Prefix-spoke1-vm-app" }
    @{ rg = $Spoke2Rg; vm = "$Prefix-spoke2-vm-app" }
)

foreach ($entry in $expectedVms) {
    $vm = Get-AzVM -ResourceGroupName $entry.rg -Name $entry.vm -ErrorAction SilentlyContinue
    if ($vm -and $vm.ProvisioningState -eq 'Succeeded') {
        Write-Host "  ✓ $($entry.vm) provisioned successfully"
    }
    elseif ($vm) {
        Write-Host "  ! $($entry.vm) state: $($vm.ProvisioningState)"
    }
    else {
        Write-Error "  ✗ $($entry.vm) NOT FOUND in $($entry.rg)"
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
Write-Host "Resource Groups: $OnpremRg, $HubRg, $Spoke1Rg, $Spoke2Rg"
Write-Host "Location: $Location"
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Configure DNS servers with: ./scripts/02-configure-dns-servers.ps1'
Write-Host '  2. Verify DNS resolution with: ./scripts/validate.ps1 -Phase Legacy'
Write-Host '  3. Deploy Private DNS with: ./scripts/03-deploy-private-dns.ps1'
