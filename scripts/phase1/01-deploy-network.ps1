#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Phase 1: On-Prem Network Foundation
    
.DESCRIPTION
    Deploys the on-premises network with DNS Server and Client VMs.
    
    This phase creates:
    - Virtual Network (10.10.0.0/16)
    - NAT Gateway (for outbound internet)
    - Network Security Group (SSH + DNS)
    - DNS Server VM (10.10.1.10) - no DNS config yet
    - Client VM (10.10.1.20) - minimal setup
    
.PARAMETER SshPublicKeyPath
    Path to SSH public key file for Linux VMs
    
.PARAMETER Location
    Azure region (default: centralus)
    
.PARAMETER Prefix
    Naming prefix (default: dnsmig)
    
.PARAMETER SubscriptionId
    Azure subscription ID (default: current context)

.EXAMPLE
    ./01-deploy-network.ps1 -SshPublicKeyPath ~/.ssh/dnsmig.pub
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SshPublicKeyPath,
    
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig',
    [string]$ResourceGroupName = "$Prefix-rg-onprem",
    [string]$AdminUsername = 'azureuser',
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# SETUP & VALIDATION
# ============================================================================

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'Phase 1: On-Prem Network Deployment' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# Check prerequisites
Write-Host 'Checking prerequisites...' -ForegroundColor Yellow
$missingTools = @()

# Check Azure CLI
try {
    $context = az account show --query 'id' -o tsv 2>$null
    if (-not $context) {
        throw 'Not logged in'
    }
}
catch {
    Write-Host 'Not logged into Azure. Running "az login"...' -ForegroundColor Yellow
    az login | Out-Null
}

# Check Bicep CLI
try {
    $bicepVersion = bicep --version 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "✓ Bicep CLI: $bicepVersion"
}
catch {
    $missingTools += 'Bicep CLI'
    Write-Host '✗ Bicep CLI not found. Install with: brew install bicep (macOS) or curl -Lo bicep https://aka.ms/bicep/linux && chmod +x bicep'
}

if ($missingTools) {
    Write-Host "Missing required tools: $($missingTools -join ', ')" -ForegroundColor Red
    exit 1
}

# Validate SSH key
if (-not (Test-Path $SshPublicKeyPath -PathType Leaf)) {
    Write-Error "SSH public key not found: $SshPublicKeyPath"
    exit 1
}

$sshPublicKey = Get-Content $SshPublicKeyPath -Raw
if (-not $sshPublicKey) {
    Write-Error "SSH public key file is empty: $SshPublicKeyPath"
    exit 1
}

Write-Host "✓ SSH public key loaded: $SshPublicKeyPath"
Write-Host ''

# Set subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId | Out-Null
}
else {
    $SubscriptionId = az account show --query 'id' -o tsv
}

$subscription = az account show --query 'name' -o tsv
Write-Host "✓ Using subscription: $subscription"
Write-Host ''

# ============================================================================
# LOCATE BICEP TEMPLATE
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$bicepFile = Join-Path $repoRoot 'bicep' 'phase1' 'network.bicep'

if (-not (Test-Path $bicepFile)) {
    Write-Error "Bicep template not found: $bicepFile"
    exit 1
}

Write-Host "Using Bicep template: $bicepFile" -ForegroundColor Gray
Write-Host ''

# ============================================================================
# DEPLOYMENT
# ============================================================================

Write-Host 'Deployment Configuration' -ForegroundColor Cyan
Write-Host '────────────────────────────────────────' -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName"
Write-Host "  Location: $Location"
Write-Host "  Prefix: $Prefix"
Write-Host '  VNet: 10.10.0.0/16'
Write-Host '  Subnet: 10.10.1.0/24'
Write-Host '  DNS Server IP: 10.10.1.10'
Write-Host '  Client VM IP: 10.10.1.20'
Write-Host ''

# Create resource group
Write-Host 'Creating resource group...' -ForegroundColor Yellow
az group create `
    -n $ResourceGroupName `
    -l $Location `
    --output none 2>$null

Write-Host "✓ Resource group created: $ResourceGroupName"
Write-Host ''

# Prepare parameters file
Write-Host 'Preparing deployment parameters...' -ForegroundColor Yellow
$paramsFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
$paramsContent = @{
    schema         = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = @{
        location      = @{ value = $Location }
        prefix        = @{ value = $Prefix }
        adminUsername = @{ value = $AdminUsername }
        sshPublicKey  = @{ value = $sshPublicKey }
    }
} | ConvertTo-Json -Depth 10

Set-Content -Path $paramsFile -Value $paramsContent -Force

# Deploy Bicep template
Write-Host 'Starting Bicep deployment...' -ForegroundColor Yellow
Write-Host ''

try {
    # Capture deployment output as raw string first
    $rawOutput = az deployment group create `
        -g $ResourceGroupName `
        -n "phase1-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -f $bicepFile `
        -p $paramsFile `
        -o json 2>&1

    # Check exit code before trying to parse JSON
    if ($LASTEXITCODE -ne 0) {
        Write-Host '✗ Deployment failed!' -ForegroundColor Red
        Write-Host "Error: $rawOutput" -ForegroundColor Red
        exit 1
    }

    # Parse JSON output
    $deploymentOutput = $rawOutput | ConvertFrom-Json

    Write-Host '✓ Deployment succeeded!' -ForegroundColor Green
    Write-Host ''

    # Extract outputs
    $outputs = $deploymentOutput.properties.outputs

    Write-Host 'Deployment Outputs' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────' -ForegroundColor Cyan
    Write-Host "VNet Name:              $($outputs.vnetName.value)"
    Write-Host "VNet ID:                $($outputs.vnetId.value)"
    Write-Host ''
    Write-Host "DNS Server Name:        $($outputs.dnsServerVmName.value)"
    Write-Host "DNS Server Private IP:  $($outputs.dnsServerPrivateIp.value)"
    Write-Host "DNS Server VM ID:       $($outputs.dnsServerVmId.value)"
    Write-Host ''
    Write-Host "Client VM Name:         $($outputs.clientVmName.value)"
    Write-Host "Client VM Private IP:   $($outputs.clientVmPrivateIp.value)"
    Write-Host "Client VM ID:           $($outputs.clientVmId.value)"
    Write-Host ''
    Write-Host "NAT Gateway Public IP:  $($outputs.natGatewayPublicIp.value)"
    Write-Host ''

    # Get public IPs for SSH access
    Write-Host 'Getting public IP addresses for SSH access...' -ForegroundColor Yellow
    $dnsVmPip = az vm show -d -g $ResourceGroupName -n "$Prefix-onprem-vm-dns" --query 'publicIps' -o tsv
    $clientPip = az vm show -d -g $ResourceGroupName -n "$Prefix-onprem-vm-client" --query 'publicIps' -o tsv

    Write-Host ''
    Write-Host 'SSH Access' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────' -ForegroundColor Cyan
    if ($dnsVmPip) {
        Write-Host "DNS Server:   ssh azureuser@$dnsVmPip"
    }
    else {
        Write-Host 'DNS Server:   (public IP not yet assigned)'
    }

    if ($clientPip) {
        Write-Host "Client VM:    ssh azureuser@$clientPip"
    }
    else {
        Write-Host 'Client VM:    (public IP not yet assigned)'
    }

    Write-Host ''
    Write-Host 'Next Steps' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────' -ForegroundColor Cyan
    Write-Host '1. Verify Phase 1 deployment:'
    Write-Host "   ./02-verify-network.ps1 -ResourceGroupName $ResourceGroupName -Verbose"
    Write-Host ''
    Write-Host '2. Wait 1-2 minutes for VMs to fully start and public IPs to be assigned'
    Write-Host ''
    Write-Host '3. Test connectivity to VMs:'
    if ($dnsVmPip) {
        Write-Host "   ssh azureuser@$dnsVmPip 'hostname && uptime'"
    }
    Write-Host ''
    Write-Host '4. Once verified, proceed to Phase 2 (DNS Server configuration):'
    Write-Host '   ./03-configure-dns-server.ps1 -ResourceGroupName dnsmig-rg-onprem'
    Write-Host ''

}
catch {
    Write-Host '✗ Deployment failed!' -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Clean up temp params file
    if (Test-Path $paramsFile) {
        Remove-Item $paramsFile -Force
    }
}
