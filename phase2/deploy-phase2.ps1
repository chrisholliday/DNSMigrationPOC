<#
.SYNOPSIS
    Phase 2 – Create VNet peerings for the DNS Migration POC.

.DESCRIPTION
    Creates six bidirectional VNet peerings:
      - On-Prem ↔ Hub
      - Hub ↔ Spoke1
      - Hub ↔ Spoke2

    After this phase, cross-VNet traffic flows freely. DNS resolution
    still uses Azure DNS — custom DNS servers are activated in Phase 4.

.PARAMETER Location
    Azure region used to scope the subscription-level deployment.
    Must match the region used in Phase 1. Default: centralus.

.EXAMPLE
    .\deploy-phase2.ps1

.NOTES
    Prerequisite: Phase 1 must be deployed successfully.
    Run 'az login' and 'az account set --subscription <id>' before executing.
#>

[CmdletBinding()]
param(
    [string] $Location = 'centralus'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Verify Azure CLI is logged in ─────────────────────────────────────────────

Write-Host 'Verifying Azure CLI authentication...' -ForegroundColor Cyan
$account = az account show --output json 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}

Write-Host "  Subscription : $($account.name)" -ForegroundColor Green
Write-Host "  Subscription ID: $($account.id)" -ForegroundColor Green

# ── Validate Phase 1 resource groups exist ────────────────────────────────────

Write-Host ''
Write-Host 'Validating Phase 1 resource groups exist...' -ForegroundColor Cyan

$requiredRgs = @('rg-dnsmig-onprem', 'rg-dnsmig-hub', 'rg-dnsmig-spoke1', 'rg-dnsmig-spoke2')
foreach ($rg in $requiredRgs) {
    $exists = az group exists --name $rg --output tsv 2>&1
    if ($exists -ne 'true') {
        Write-Error "Resource group '$rg' not found. Deploy Phase 1 first."
        exit 1
    }
    Write-Host "  Found: $rg" -ForegroundColor Green
}

# ── Deploy ────────────────────────────────────────────────────────────────────

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$bicepFile = Join-Path $scriptDir 'main.bicep'

if (-not (Test-Path -Path $bicepFile)) {
    Write-Error "Bicep file not found: $bicepFile"
    exit 1
}

$deploymentName = "phase2-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host ''
Write-Host 'Starting Phase 2 deployment (VNet peerings)...' -ForegroundColor Cyan
Write-Host "  Deployment name : $deploymentName"
Write-Host ''

$deployOutput = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $bicepFile `
    --output json `
    --only-show-errors 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Phase 2 deployment failed.`n$deployOutput"
    exit 1
}

Write-Host ''
Write-Host 'Phase 2 complete. VNet peerings established:' -ForegroundColor Green
Write-Host '  On-Prem (vnet-onprem) ↔ Hub (vnet-hub)' -ForegroundColor Green
Write-Host '  Hub (vnet-hub) ↔ Spoke1 (vnet-spoke1)' -ForegroundColor Green
Write-Host '  Hub (vnet-hub) ↔ Spoke2 (vnet-spoke2)' -ForegroundColor Green
Write-Host ''

# ── Quick connectivity validation ─────────────────────────────────────────────
# Verify peering states are 'Connected' on both sides.

Write-Host 'Validating peering states...' -ForegroundColor Cyan

$peeringPairs = @(
    @{ rg = 'rg-dnsmig-onprem'; vnet = 'vnet-onprem'; peering = 'onprem-to-hub' },
    @{ rg = 'rg-dnsmig-hub'; vnet = 'vnet-hub'; peering = 'hub-to-onprem' },
    @{ rg = 'rg-dnsmig-hub'; vnet = 'vnet-hub'; peering = 'hub-to-spoke1' },
    @{ rg = 'rg-dnsmig-spoke1'; vnet = 'vnet-spoke1'; peering = 'spoke1-to-hub' },
    @{ rg = 'rg-dnsmig-hub'; vnet = 'vnet-hub'; peering = 'hub-to-spoke2' },
    @{ rg = 'rg-dnsmig-spoke2'; vnet = 'vnet-spoke2'; peering = 'spoke2-to-hub' }
)

$allConnected = $true
foreach ($pair in $peeringPairs) {
    $state = az network vnet peering show `
        --resource-group $pair.rg `
        --vnet-name $pair.vnet `
        --name $pair.peering `
        --query 'peeringState' `
        --output tsv `
        --only-show-errors 2>&1

    if ($state -eq 'Connected') {
        Write-Host ('  {0,-35} {1}' -f "$($pair.vnet)/$($pair.peering):", $state) -ForegroundColor Green
    }
    else {
        Write-Host ('  {0,-35} {1}' -f "$($pair.vnet)/$($pair.peering):", $state) -ForegroundColor Yellow
        $allConnected = $false
    }
}

if ($allConnected) {
    Write-Host ''
    Write-Host 'All peerings are Connected.' -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host 'Some peerings are not yet Connected. This may resolve within a few minutes.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next step: Run phase3\configure-dns.ps1 to configure BIND9 on the DNS servers.' -ForegroundColor Cyan
