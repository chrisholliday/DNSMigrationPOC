#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploys Phase 1 - Complete infrastructure for DNS migration POC.

.DESCRIPTION
Creates both on-prem and hub resource groups and deploys VNets, VMs, Bastion, and NAT Gateways.
All VMs use Azure DNS (168.63.129.16) - no custom DNS or peering at this stage.

VNet Peering and DNS configuration will be done in subsequent phases.

.PARAMETER Location
Azure region for deployment. Default: centralus

.PARAMETER SubscriptionId
Azure subscription ID. If not provided, uses current subscription context.

.PARAMETER SshPublicKeyPath
Path to SSH public key file. If not provided, uses ~/.ssh/id_rsa.pub

.PARAMETER Force
Skip confirmation prompts and deploy immediately.

.EXAMPLE
./phase1-deploy.ps1 -Location "eastus" -Force

.EXAMPLE
./phase1-deploy.ps1 -SshPublicKeyPath ~/.ssh/dnsmig.pub

#>

param(
    [string]$Location = 'centralus',
    [string]$SubscriptionId,
    [string]$SshPublicKeyPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:deploymentStartTime = Get-Date

# Configuration
$OnpremResourceGroupName = 'rg-onprem-dnsmig'
$HubResourceGroupName = 'rg-hub-dnsmig'
$DeploymentName = "phase1-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$BicepTemplatePath = Join-Path $PSScriptRoot '../bicep/phase1-main.bicep'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1 Deployment - Infrastructure Foundation           ║' -ForegroundColor Cyan
Write-Host '║  Deploys: On-Prem + Hub VNets (Azure DNS only)            ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Validate prerequisites
Write-Host '[1/6] Validating prerequisites...' -ForegroundColor Yellow

# Check Azure CLI/PowerShell modules
if (-not (Get-Command az -ErrorAction SilentlyContinue) -and -not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error 'Azure CLI or Az PowerShell module not found. Please install: https://aka.ms/azure-cli or Install-Module -Name Az -Force'
}

# Import Az modules if available
if (Get-Module -ListAvailable -Name Az.Accounts) {
    Import-Module Az.Accounts -ErrorAction SilentlyContinue | Out-Null
    Import-Module Az.Resources -ErrorAction SilentlyContinue | Out-Null
    Write-Host '✓ Az PowerShell modules loaded' -ForegroundColor Green
}

# Validate Bicep template exists
if (-not (Test-Path $BicepTemplatePath)) {
    Write-Error "Bicep template not found at: $BicepTemplatePath"
}

# Handle SSH public key
if (-not $SshPublicKeyPath) {
    # Try common locations
    $commonPaths = @(
        (Join-Path $HOME '.ssh/id_rsa.pub'),
        (Join-Path $HOME '.ssh/dnsmig.pub')
    )
    
    $SshPublicKeyPath = $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $SshPublicKeyPath) {
        Write-Host ''
        Write-Host '❌ SSH public key not found in common locations:' -ForegroundColor Red
        $commonPaths | ForEach-Object { Write-Host "   - $_" }
        Write-Host ''
        Write-Host "Generate a key with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig -C 'dnsmig'" -ForegroundColor Yellow
        Write-Error 'SSH public key required for VM deployment'
    }
}

if (-not (Test-Path $SshPublicKeyPath)) {
    Write-Error "SSH public key not found at: $SshPublicKeyPath"
}

$sshPublicKey = Get-Content $SshPublicKeyPath -Raw
Write-Host "✓ SSH public key loaded from: $SshPublicKeyPath" -ForegroundColor Green
Write-Host "✓ Bicep template found: $BicepTemplatePath" -ForegroundColor Green

# Set Azure subscription
Write-Host ''
Write-Host '[2/6] Setting Azure context...' -ForegroundColor Yellow

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to set subscription'
    }
    Write-Host "✓ Subscription set to: $SubscriptionId" -ForegroundColor Green
}
else {
    $currentSub = az account show --query 'id' -o tsv
    Write-Host "✓ Using current subscription: $currentSub" -ForegroundColor Green
}

# Validate Bicep template
Write-Host ''
Write-Host '[3/5] Validating Bicep template...' -ForegroundColor Yellow

az bicep build --file $BicepTemplatePath --outfile (Join-Path $PSScriptRoot '../bicep/.phase1.json') `
    2>&1 | Where-Object { $_ -match 'error|warning' } | ForEach-Object { Write-Host "  ⚠ $_" }

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Bicep template validation failed'
}
Write-Host '✓ Bicep template validated' -ForegroundColor Green

# Confirm deployment
if (-not $Force) {
    Write-Host ''
    Write-Host 'About to deploy:' -ForegroundColor Yellow
    Write-Host "  - On-prem Resource Group: $OnpremResourceGroupName" -ForegroundColor White
    Write-Host '    VNet (10.0.0.0/16) with 2 VMs, Bastion, NAT Gateway' -ForegroundColor White
    Write-Host "  - Hub Resource Group: $HubResourceGroupName" -ForegroundColor White
    Write-Host '    VNet (10.1.0.0/16) with 2 VMs, Bastion, NAT Gateway' -ForegroundColor White
    Write-Host '  - Azure DNS (168.63.129.16) for all VMs' -ForegroundColor White
    Write-Host "  - NO VNet peering (that's Phase 2)" -ForegroundColor White
    Write-Host '  - NO custom DNS (configured in Phases 3-6)' -ForegroundColor White
    Write-Host ''
    $confirmation = Read-Host 'Continue with deployment? (y/n)'
    if ($confirmation -ne 'y') {
        Write-Host 'Deployment cancelled' -ForegroundColor Yellow
        exit 0
    }
}

# Deploy Bicep template at subscription level (creates resource groups and all resources)
Write-Host ''
Write-Host '[4/5] Deploying infrastructure (this may take 10-15 minutes)...' -ForegroundColor Yellow
Write-Host ''

$deploymentParams = @{
    Location                = $Location
    TemplateFile            = $BicepTemplatePath
    TemplateParameterObject = @{
        location                = $Location
        sshPublicKey            = $sshPublicKey.Trim()
        vmAdminUsername         = 'azureuser'
        onpremResourceGroupName = $OnpremResourceGroupName
        hubResourceGroupName    = $HubResourceGroupName
    }
    DeploymentName          = $DeploymentName
    ErrorAction             = 'Stop'
}

try {
    # Subscription-level deployment
    $deployment = New-AzSubscriptionDeployment @deploymentParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host ''
        Write-Host '✓ Deployment completed successfully!' -ForegroundColor Green
        
        # Show outputs
        Write-Host ''
        Write-Host 'Deployment Outputs:' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  On-Prem Environment:' -ForegroundColor Yellow
        Write-Host "    VNet:             $($deployment.Outputs.onpremVnetName.Value)" -ForegroundColor White
        Write-Host "    DNS VM IP:        $($deployment.Outputs.onpremDnsVmPrivateIp.Value)" -ForegroundColor White
        Write-Host "    Client VM IP:     $($deployment.Outputs.onpremClientVmPrivateIp.Value)" -ForegroundColor White
        Write-Host "    Bastion:          $($deployment.Outputs.onpremBastionName.Value)" -ForegroundColor White
        Write-Host "    NAT Gateway IP:   $($deployment.Outputs.onpremNatGatewayPublicIp.Value)" -ForegroundColor White
        Write-Host ''
        Write-Host '  Hub Environment:' -ForegroundColor Yellow
        Write-Host "    VNet:             $($deployment.Outputs.hubVnetName.Value)" -ForegroundColor White
        Write-Host "    DNS VM IP:        $($deployment.Outputs.hubDnsVmPrivateIp.Value)" -ForegroundColor White
        Write-Host "    App VM IP:        $($deployment.Outputs.hubAppVmPrivateIp.Value)" -ForegroundColor White
        Write-Host "    Bastion:          $($deployment.Outputs.hubBastionName.Value)" -ForegroundColor White
        Write-Host "    NAT Gateway IP:   $($deployment.Outputs.hubNatGatewayPublicIp.Value)" -ForegroundColor White
        
        # Show summary
        $elapsedTime = (Get-Date) - $script:deploymentStartTime
        Write-Host ''
        Write-Host 'Summary:' -ForegroundColor Cyan
        Write-Host "  On-prem Resource Group: $OnpremResourceGroupName" -ForegroundColor White
        Write-Host "  Hub Resource Group:     $HubResourceGroupName" -ForegroundColor White
        Write-Host "  Location:               $Location" -ForegroundColor White
        Write-Host "  Deployment Time:        $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s" -ForegroundColor White
        Write-Host '  DNS Mode:               Azure DNS (168.63.129.16)' -ForegroundColor White
        Write-Host '  VNet Peering:           Not configured (Phase 2)' -ForegroundColor White
        
        Write-Host ''
        Write-Host 'Next Steps:' -ForegroundColor Cyan
        Write-Host '  1. Run validation tests:' -ForegroundColor White
        Write-Host '     ./scripts/phase1-test.ps1' -ForegroundColor Green
        Write-Host '  2. Verify VMs can access internet and update packages' -ForegroundColor White
        Write-Host '  3. Connect to VMs via Azure Bastion in the Azure Portal' -ForegroundColor White
        Write-Host '  4. When ready, establish connectivity:' -ForegroundColor White
        Write-Host '     ./scripts/phase2-deploy.ps1  # VNet peering' -ForegroundColor Green
        
        Write-Host ''
        Write-Host 'Architecture Notes:' -ForegroundColor Cyan
        Write-Host '  - Both VNets are isolated (no peering yet)' -ForegroundColor White
        Write-Host '  - All VMs use Azure DNS for now' -ForegroundColor White
        Write-Host '  - Custom DNS will be configured after connectivity is established' -ForegroundColor White
        
        exit 0
    }
    else {
        Write-Host ''
        Write-Host "❌ Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host ''
    Write-Host '❌ Deployment error:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host 'Troubleshooting:' -ForegroundColor Yellow
    Write-Host "  - Check SSH key path: $SshPublicKeyPath" -ForegroundColor White
    Write-Host "  - Verify Bicep syntax: az bicep build $BicepTemplatePath" -ForegroundColor White
    Write-Host '  - Review deployment details in Azure Portal' -ForegroundColor White
    Write-Host "  - Check resource group: $OnpremResourceGroupName" -ForegroundColor White
    exit 1
}
