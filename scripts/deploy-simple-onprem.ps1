#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy simplified on-prem DNS environment for POC.
    
.DESCRIPTION
    This script deploys a minimal on-prem network topology with:
    - One VNet with DNS server (dnsmasq) and client VM
    - NAT Gateway for internet connectivity
    - dnsmasq configured to host onprem.pvt zone
    
.PARAMETER SshPublicKeyPath
    Path to SSH public key file for Linux VMs
    
.PARAMETER Location
    Azure region (default: centralus)
    
.PARAMETER Prefix
    Naming prefix (default: dnsmig)
    
.PARAMETER SubscriptionId
    Azure subscription ID (uses current context if not specified)

.EXAMPLE
    ./deploy-simple-onprem.ps1 -SshPublicKeyPath ~/.ssh/id_rsa.pub
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
Write-Host 'DNS Migration POC - Simple On-Prem Deployment' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI and Bicep
Write-Host 'Checking prerequisites...' -ForegroundColor Yellow
$missingTools = @()

# Check if logged into Azure
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

# Check for Bicep CLI
try {
    $bicepVersion = bicep --version 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "✓ Bicep CLI: $bicepVersion"
}
catch {
    $missingTools += 'Bicep CLI'
    Write-Host '✗ Bicep CLI not found. Install with: curl -Lo bicep https://aka.ms/bicep/linux && chmod +x ./bicep'
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

# Get or set subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId | Out-Null
}
else {
    $SubscriptionId = az account show --query 'id' -o tsv
}

$subscription = az account show --query 'name' -o tsv
Write-Host "✓ Using subscription: $subscription ($SubscriptionId)"
Write-Host ''

# ============================================================================
# BICEP FILE LOCATION
# ============================================================================

$scriptDir = Split-Path -Parent $PSScriptRoot
$bicepFile = Join-Path $scriptDir 'bicep' 'simple-onprem.bicep'

if (-not (Test-Path $bicepFile)) {
    Write-Error "Bicep template not found: $bicepFile"
    exit 1
}

Write-Host "Using Bicep template: $bicepFile" -ForegroundColor Gray
Write-Host ''

# ============================================================================
# DEPLOYMENT
# ============================================================================

Write-Host 'Starting deployment...' -ForegroundColor Cyan
Write-Host "  Location: $Location"
Write-Host "  Prefix: $Prefix"
Write-Host "  Resource Group: $ResourceGroupName"
Write-Host ''

# Create resource group first
Write-Host 'Creating resource group...' -ForegroundColor Yellow
az group create -n $ResourceGroupName -l $Location --output none

# Create a temporary parameters file for the deployment
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
} | ConvertTo-Json -Depth 10 -EnumsAsStrings

$paramsContent | Out-File -FilePath $paramsFile -Encoding UTF8 -Force

try {
    Write-Host 'Deploying infrastructure...' -ForegroundColor Yellow
    
    $deployment = az deployment group create `
        -g $ResourceGroupName `
        --template-file $bicepFile `
        --parameters $paramsFile `
        --output json | ConvertFrom-Json
    
    if ($deployment.properties.provisioningState -eq 'Succeeded') {
        Write-Host '✓ Deployment succeeded!' -ForegroundColor Green
    }
    else {
        Write-Error "Deployment failed with state: $($deployment.properties.provisioningState)"
        Write-Host $deployment | ConvertTo-Json
        exit 1
    }
    
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
}
finally {
    # Clean up temporary parameters file
    if (Test-Path $paramsFile) {
        Remove-Item $paramsFile -Force
    }
}

# ============================================================================
# POST-DEPLOYMENT INFORMATION
# ============================================================================

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host 'Deployment Complete!' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''

$outputs = $deployment.properties.outputs

Write-Host 'Key Outputs:' -ForegroundColor Cyan
Write-Host "  Resource Group: $($outputs.resourceGroupName.value)"
Write-Host "  DNS Server VM: $($outputs.dnsServerVmName.value)"
Write-Host "  DNS Server IP: $($outputs.dnsServerPrivateIp.value)"
Write-Host "  Client VM: $($outputs.clientVmName.value)"
Write-Host "  VNet: $($outputs.vnetName.value)"
Write-Host ''

# ============================================================================
# NEXT STEPS
# ============================================================================

Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '1. Wait for cloud-init to complete:' -ForegroundColor Cyan
Write-Host "   ./scripts/wait-for-cloudinit.ps1 -ResourceGroupName $ResourceGroupName -VmNames '$($outputs.dnsServerVmName.value),$($outputs.clientVmName.value)'"
Write-Host ''
Write-Host '   OR manually wait 2-3 minutes, then continue to step 2.'
Write-Host ''
Write-Host "2. SSH to DNS server: az ssh vm -g $ResourceGroupName -n $($outputs.dnsServerVmName.value) --local-user $AdminUsername"
Write-Host "3. SSH to client VM:  az ssh vm -g $ResourceGroupName -n $($outputs.clientVmName.value) --local-user $AdminUsername"
Write-Host "4. Run verification script: ./scripts/verify-dns.ps1 -ResourceGroupName $ResourceGroupName -DnsServerName $($outputs.dnsServerVmName.value) -ClientName $($outputs.clientVmName.value)"
Write-Host ''

Write-Host 'DNS Configuration:' -ForegroundColor Cyan
Write-Host '  - DNS Domain: onprem.pvt'
Write-Host "  - DNS Server: $($outputs.dnsServerPrivateIp.value)"
Write-Host '  - Configuration: /etc/dnsmasq.d/onprem.conf'
Write-Host ''

Write-Host 'To view logs:' -ForegroundColor Cyan
Write-Host "  az vm run-command invoke -g $ResourceGroupName -n $($outputs.dnsServerVmName.value) --command-id RunShellScript --scripts 'journalctl -u dnsmasq -n 20'"
Write-Host ''
