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
Write-Host 'Phase 2: Deploy Legacy Environment (Multi-RG)'
Write-Host '=================================================='

Write-Host 'Deploying VNets, peerings, and VMs...'
$bicepFile = Join-Path $root 'bicep\legacy.bicep'
$deployParams = @{
    Location                = $Location
    TemplateFile            = $bicepFile
    TemplateParameterObject = @{
        location      = $Location
        prefix        = $Prefix
        adminUsername = $AdminUsername
        sshPublicKey  = $sshPublicKey
        rgNames       = $rgNames
    }
}

# Deploy with retry logic for transient Azure API errors
$maxRetries = 5
$retryCount = 0
$deployment = $null
$retryDelaySeconds = 60

do {
    $retryCount++
    try {
        $deployment = New-AzDeployment @deployParams -ErrorAction Stop
        break
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match 'AnotherOperationInProgress' -and $retryCount -lt $maxRetries) {
            Write-Host "  ⚠ Transient error: Another operation in progress. Retrying in $retryDelaySeconds seconds (attempt $retryCount/$maxRetries)..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
        elseif ($errorMessage -match 'InUseSubnetCannotBeDeleted') {
            Write-Error 'Deployment failed: Resources from a previous deployment exist and are blocking this deployment.'
            Write-Host ''
            Write-Host 'To clean up existing resources, run: ./scripts/teardown.ps1'
            Write-Host 'Then retry this deployment script.'
            exit 1
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

if ($deployment.ProvisioningState -ne 'Succeeded') {
    Write-Error "Deployment failed: $($deployment.ProvisioningState)"
    exit 1
}

Write-Host '✓ Phase 2 Complete: Legacy environment deployed'
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
    @{ rg = $OnpremRg; vnet = "$Prefix-onprem-vnet"; peering = 'peer-onprem-to-hub' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'peer-hub-to-onprem' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'peer-hub-to-spoke1' }
    @{ rg = $Spoke1Rg; vnet = "$Prefix-spoke1-vnet"; peering = 'peer-spoke1-to-hub' }
    @{ rg = $HubRg; vnet = "$Prefix-hub-vnet"; peering = 'peer-hub-to-spoke2' }
    @{ rg = $Spoke2Rg; vnet = "$Prefix-spoke2-vnet"; peering = 'peer-spoke2-to-hub' }
)

foreach ($peer in $expectedPeerings) {
    $p = Get-AzVirtualNetworkPeering -ResourceGroupName $peer.rg -VirtualNetworkName $peer.vnet -Name $peer.peering -ErrorAction SilentlyContinue
    if ($p -and $p.PeeringState -eq 'Connected') {
        Write-Host "  ✓ $($peer.vnet) -> $($peer.peering) is Connected"
    }
    elseif ($p) {
        Write-Error "  ✗ $($peer.vnet) -> $($peer.peering) state: $($p.PeeringState) (expected Connected)"
        exit 1
    }
    else {
        Write-Error "  ✗ $($peer.vnet) -> $($peer.peering) NOT FOUND"
        exit 1
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
