<#
.SYNOPSIS
    Phase 1 – Deploy foundation infrastructure for the DNS Migration POC.

.DESCRIPTION
    Deploys four resource groups and their core resources:
      - rg-dnsmig-onprem  (on-prem VNet, DNS VM, Bastion, NAT GW)
      - rg-dnsmig-hub     (hub VNet, DNS VM, Bastion, NAT GW)
      - rg-dnsmig-spoke1  (spoke1 VNet, workload VM, Storage account, Private Endpoint)
      - rg-dnsmig-spoke2  (spoke2 VNet, workload VM, Storage account, Private Endpoint)

    All VNets use Azure DNS at this stage. Custom DNS servers are activated in Phase 4.

.PARAMETER SshPublicKeyPath
    Path to the SSH public key file (e.g. ~/.ssh/id_rsa.pub).
    The key is read and passed to the Bicep deployment.

.PARAMETER AdminUsername
    Username for the VM OS. Default: azureuser.

.PARAMETER Location
    Azure region for all resources. Default: centralus.

.PARAMETER VmSize
    VM size for all virtual machines. Default: Standard_B2s.

.EXAMPLE
    .\deploy-phase1.ps1 -SshPublicKeyPath ~/.ssh/id_rsa.pub

.NOTES
    Requires: Azure CLI (az) and Bicep installed.
    Run 'az login' and 'az account set --subscription <id>' before executing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SshPublicKeyPath,

    [string] $AdminUsername = 'azureuser',

    [string] $Location = 'centralus',

    [string] $VmSize = 'Standard_B2s'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Validate inputs ───────────────────────────────────────────────────────────

if (-not (Test-Path -Path $SshPublicKeyPath)) {
    Write-Error "SSH public key file not found: $SshPublicKeyPath"
    exit 1
}

$sshPublicKey = (Get-Content -Path $SshPublicKeyPath -Raw -ErrorAction Stop).Trim()
if ([string]::IsNullOrWhiteSpace($sshPublicKey)) {
    Write-Error "SSH public key file is empty: $SshPublicKeyPath"
    exit 1
}

Write-Verbose "SSH public key loaded from: $SshPublicKeyPath"

# ── Verify Azure CLI is logged in ─────────────────────────────────────────────

Write-Host 'Verifying Azure CLI authentication...' -ForegroundColor Cyan
$account = az account show --output json 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}

Write-Host "  Subscription : $($account.name)" -ForegroundColor Green
Write-Host "  Subscription ID: $($account.id)" -ForegroundColor Green
Write-Host "  Tenant       : $($account.tenantId)" -ForegroundColor Green

# ── Build deployment parameters ───────────────────────────────────────────────

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$bicepFile = Join-Path $scriptDir 'main.bicep'

if (-not (Test-Path -Path $bicepFile)) {
    Write-Error "Bicep file not found: $bicepFile"
    exit 1
}

$deploymentName = "phase1-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host ''
Write-Host 'Starting Phase 1 deployment...' -ForegroundColor Cyan
Write-Host "  Deployment name : $deploymentName"
Write-Host "  Location        : $Location"
Write-Host "  Admin username  : $AdminUsername"
Write-Host "  VM size         : $VmSize"
Write-Host ''

# ── Deploy ────────────────────────────────────────────────────────────────────

$deployOutput = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $bicepFile `
    --parameters `
    adminUsername=$AdminUsername `
    sshPublicKey=$sshPublicKey `
    location=$Location `
    vmSize=$VmSize `
    --output json `
    --only-show-errors 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Phase 1 deployment failed.`n$deployOutput"
    exit 1
}

# ── Parse and display outputs ─────────────────────────────────────────────────

try {
    $result = $deployOutput | ConvertFrom-Json
    $outputs = $result.properties.outputs
}
catch {
    Write-Error "Failed to parse deployment output: $_"
    exit 1
}

Write-Host ''
Write-Host 'Phase 1 deployment complete.' -ForegroundColor Green
# ── Write state file ─────────────────────────────────────────────────────────
# phase1-outputs.json is read by configure-dns.ps1 (Phase 3) and deploy-phase4.ps1 (Phase 4).
# It is excluded from source control via .gitignore.

$stateFile = Join-Path (Split-Path -Parent $scriptDir) 'phase1-outputs.json'

$state = [ordered]@{
    onpremVmPrivateIp         = $outputs.onpremVmPrivateIp.value
    hubVmPrivateIp            = $outputs.hubVmPrivateIp.value
    spoke1VmPrivateIp         = $outputs.spoke1VmPrivateIp.value
    spoke2VmPrivateIp         = $outputs.spoke2VmPrivateIp.value
    spoke1StorageAccountName  = $outputs.spoke1StorageAccountName.value
    spoke2StorageAccountName  = $outputs.spoke2StorageAccountName.value
    spoke1PrivateEndpointName = $outputs.spoke1PrivateEndpointName.value
    spoke2PrivateEndpointName = $outputs.spoke2PrivateEndpointName.value
}

$state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
Write-Host "State file written: $stateFile" -ForegroundColor Green

Write-Host ''
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Deployment Outputs (needed for Phase 3 and 4)' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$outputTable = [ordered]@{
    'vm-onprem-dns IP'        = $state.onpremVmPrivateIp
    'vm-hub-dns IP'           = $state.hubVmPrivateIp
    'vm-spoke1 IP'            = $state.spoke1VmPrivateIp
    'vm-spoke2 IP'            = $state.spoke2VmPrivateIp
    'Spoke1 Storage Account'  = $state.spoke1StorageAccountName
    'Spoke2 Storage Account'  = $state.spoke2StorageAccountName
    'Spoke1 Private Endpoint' = $state.spoke1PrivateEndpointName
    'Spoke2 Private Endpoint' = $state.spoke2PrivateEndpointName
}

foreach ($key in $outputTable.Keys) {
    Write-Host ('  {0,-30} {1}' -f "${key}:", $outputTable[$key])
}

Write-Host ''
Write-Host 'Next step: Run phase2\deploy-phase2.ps1 to establish VNet peering.' -ForegroundColor Cyan
