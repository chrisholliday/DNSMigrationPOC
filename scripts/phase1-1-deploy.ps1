#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploys Phase 1.1 - On-Prem infrastructure for DNS migration POC.

.DESCRIPTION
Creates resource group, VNet, subnets, NAT Gateway, Azure Bastion, and 2 VMs in the on-prem environment.
Does not configure DNS - that is Phase 1.2.

.PARAMETER Location
Azure region for deployment. Default: centralus

.PARAMETER SubscriptionId
Azure subscription ID. If not provided, uses current subscription context.

.PARAMETER SshPublicKeyPath
Path to SSH public key file. If not provided, uses ~/.ssh/id_rsa.pub

.PARAMETER Force
Skip confirmation prompts and deploy immediately.

.EXAMPLE
./phase1-1-deploy.ps1 -Location "eastus" -Force

.EXAMPLE
./phase1-1-deploy.ps1 -SshPublicKeyPath ~/.ssh/dnsmig.pub

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
$ResourceGroupName = 'rg-onprem-dnsmig'
$DeploymentName = "phase1-1-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$BicepTemplatePath = Join-Path $PSScriptRoot '../bicep/phase1-1-main.bicep'
$EnvironmentName = 'onprem'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.1 Deployment - On-Prem Infrastructure            ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Validate prerequisites
Write-Host '[1/5] Validating prerequisites...' -ForegroundColor Yellow

# Check Azure CLI/PowerShell modules
if (-not (Get-Command az -ErrorAction SilentlyContinue) -and -not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error 'Azure CLI or Az PowerShell module not found. Please install: https://aka.ms/azure-cli or Install-Module -Name Az -Force'
}

# Import Az modules if available (for New-AzResourceGroupDeployment)
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
Write-Host '[2/5] Setting Azure context...' -ForegroundColor Yellow

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

# Create resource group
Write-Host ''
Write-Host "[3/5] Creating resource group: $ResourceGroupName" -ForegroundColor Yellow

az group create `
    --name $ResourceGroupName `
    --location $Location | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to create resource group'
}
Write-Host '✓ Resource group created/updated' -ForegroundColor Green

# Validate Bicep template
Write-Host ''
Write-Host '[4/5] Validating Bicep template...' -ForegroundColor Yellow

az bicep build --file $BicepTemplatePath --outfile (Join-Path $PSScriptRoot '../bicep/.phase1-1.json') `
    2>&1 | Where-Object { $_ -match 'error|warning' } | ForEach-Object { Write-Host "  ⚠ $_" }

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Bicep template validation failed'
}
Write-Host '✓ Bicep template validated' -ForegroundColor Green

# Deploy Bicep template
Write-Host ''
Write-Host '[5/5] Deploying infrastructure (this may take 5-10 minutes)...' -ForegroundColor Yellow
Write-Host ''

$deploymentParams = @{
    ResourceGroupName       = $ResourceGroupName
    TemplateFile            = $BicepTemplatePath
    TemplateParameterObject = @{
        location        = $Location
        environmentName = $EnvironmentName
        sshPublicKey    = $sshPublicKey.Trim()
        vmAdminUsername = 'azureuser'
    }
    DeploymentName          = $DeploymentName
    ErrorAction             = 'Stop'
}

try {
    $deployment = New-AzResourceGroupDeployment @deploymentParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host ''
        Write-Host '✓ Deployment completed successfully!' -ForegroundColor Green
        
        # Show outputs
        Write-Host ''
        Write-Host 'Deployment Outputs:' -ForegroundColor Cyan
        $deployment.Outputs | ForEach-Object {
            $_.GetEnumerator() | ForEach-Object {
                Write-Host "  $($_.Key): $($_.Value.Value)" -ForegroundColor White
            }
        }
        
        # Show summary
        $elapsedTime = (Get-Date) - $script:deploymentStartTime
        Write-Host ''
        Write-Host 'Summary:' -ForegroundColor Cyan
        Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
        Write-Host "  Location: $Location" -ForegroundColor White
        Write-Host "  Deployment Time: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s" -ForegroundColor White
        
        Write-Host ''
        Write-Host 'Next Steps:' -ForegroundColor Cyan
        Write-Host '  1. Run validation tests:' -ForegroundColor White
        Write-Host '     ./scripts/phase1-1-test.ps1' -ForegroundColor Green
        Write-Host '  2. Connect to VMs via Azure Bastion in the Azure Portal' -ForegroundColor White
        Write-Host '  3. When done, clean up with:' -ForegroundColor White
        Write-Host '     ./scripts/phase1-1-teardown.ps1' -ForegroundColor Green
        
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
    Write-Host "  - Verify Bicep syntax: az bicep build $(Join-Path $PSScriptRoot '../bicep/phase1-1-main.bicep')" -ForegroundColor White
    Write-Host '  - Review deployment details in Azure Portal' -ForegroundColor White
    exit 1
}
