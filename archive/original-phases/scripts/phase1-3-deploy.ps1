#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploys Phase 1.3 - Hub infrastructure for DNS migration POC.

.DESCRIPTION
Creates Hub resource group, VNet, subnets, NAT Gateway, Azure Bastion, and 2 VMs.
Configures VNet DNS to point to on-prem DNS server.
Establishes VNet peering between Hub and On-Prem.
Requires Phase 1.2 to be deployed first (on-prem DNS must be operational).

.PARAMETER Location
Azure region for deployment. Default: centralus

.PARAMETER SubscriptionId
Azure subscription ID. If not provided, uses current subscription context.

.PARAMETER SshPublicKeyPath
Path to SSH public key file. If not provided, uses ~/.ssh/id_rsa.pub

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER Force
Skip confirmation prompts and deploy immediately.

.EXAMPLE
./phase1-3-deploy.ps1 -Force

.EXAMPLE
./phase1-3-deploy.ps1 -Location "eastus" -Force
#>

param(
    [string]$Location = 'centralus',
    [string]$SubscriptionId,
    [string]$SshPublicKeyPath,
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:deploymentStartTime = Get-Date

# Configuration
$ResourceGroupName = 'rg-hub-dnsmig'
$DeploymentName = "phase1-3-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$BicepTemplatePath = Join-Path $PSScriptRoot '../bicep/phase1-3-main.bicep'
$EnvironmentName = 'hub'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.3 Deployment - Hub Infrastructure                 ║' -ForegroundColor Cyan
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

# Validate on-prem deployment exists
Write-Host ''
Write-Host '[2/6] Validating on-prem deployment...' -ForegroundColor Yellow

$onpremRgExists = az group exists --name $OnpremResourceGroupName
if ($onpremRgExists -eq 'false') {
    Write-Error "On-prem resource group '$OnpremResourceGroupName' not found. Deploy Phase 1.2 first."
}

# Get on-prem VNet ID
$onpremVnetId = az network vnet list `
    --resource-group $OnpremResourceGroupName `
    --query '[0].id' -o tsv

if (-not $onpremVnetId -or $LASTEXITCODE -ne 0) {
    Write-Error "Failed to get on-prem VNet ID from resource group: $OnpremResourceGroupName"
}

# Get on-prem DNS VM IP
$onpremDnsVmName = 'onprem-vm-dns'
$onpremDnsIp = az vm show -d `
    --resource-group $OnpremResourceGroupName `
    --name $onpremDnsVmName `
    --query 'privateIps' -o tsv

if (-not $onpremDnsIp -or $LASTEXITCODE -ne 0) {
    Write-Error "Failed to get on-prem DNS VM IP. Ensure '$onpremDnsVmName' exists in $OnpremResourceGroupName"
}

Write-Host "✓ On-prem VNet found: $onpremVnetId" -ForegroundColor Green
Write-Host "✓ On-prem DNS IP: $onpremDnsIp" -ForegroundColor Green

# Set Azure subscription
Write-Host ''
Write-Host '[3/6] Setting Azure context...' -ForegroundColor Yellow

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
Write-Host "[4/6] Creating resource group: $ResourceGroupName" -ForegroundColor Yellow

az group create `
    --name $ResourceGroupName `
    --location $Location | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to create resource group'
}
Write-Host '✓ Resource group created/updated' -ForegroundColor Green

# Validate Bicep template
Write-Host ''
Write-Host '[5/6] Validating Bicep template...' -ForegroundColor Yellow

az bicep build --file $BicepTemplatePath --outfile (Join-Path $PSScriptRoot '../bicep/.phase1-3.json') `
    2>&1 | Where-Object { $_ -match 'error|warning' } | ForEach-Object { Write-Host "  ⚠ $_" }

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Bicep template validation failed'
}
Write-Host '✓ Bicep template validated' -ForegroundColor Green

# Deploy Bicep template
Write-Host ''
Write-Host '[6/6] Deploying infrastructure (this may take 5-10 minutes)...' -ForegroundColor Yellow
Write-Host ''

$deploymentParams = @{
    ResourceGroupName       = $ResourceGroupName
    TemplateFile            = $BicepTemplatePath
    TemplateParameterObject = @{
        location        = $Location
        environmentName = $EnvironmentName
        sshPublicKey    = $sshPublicKey.Trim()
        vmAdminUsername = 'azureuser'
        onpremVnetId    = $onpremVnetId
        onpremDnsIp     = $onpremDnsIp
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
        Write-Host "  On-Prem DNS: $onpremDnsIp" -ForegroundColor White
        Write-Host "  Deployment Time: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s" -ForegroundColor White
        
        Write-Host ''
        Write-Host 'Next Steps:' -ForegroundColor Cyan
        Write-Host '  1. Set up VNet peering:' -ForegroundColor White
        Write-Host '     ./scripts/phase1-3-setup-peering.ps1 -Force' -ForegroundColor Green
        Write-Host '  2. Run validation tests:' -ForegroundColor White
        Write-Host '     ./scripts/phase1-3-test.ps1' -ForegroundColor Green
        Write-Host '  3. Connect to VMs via Azure Bastion in the Azure Portal' -ForegroundColor White
        Write-Host '  4. Proceed to Phase 1.4 to configure Hub DNS services' -ForegroundColor White
        
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
    Write-Host "  - Ensure on-prem deployment exists: $OnpremResourceGroupName" -ForegroundColor White
    exit 1
}
