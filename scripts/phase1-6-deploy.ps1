#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Consolidated Phase 1-6: Complete DNS migration infrastructure and cutover.

.DESCRIPTION
This script consolidates Phases 1-6 into a single deployment for rapid POC setup:

Phase 1: Infrastructure - On-prem and Hub VNets, VMs, Bastion, NAT Gateway
Phase 2: VNet Peering - Bidirectional peering between on-prem and hub
Phase 3: On-prem DNS - Install and configure BIND9 on onprem-vm-dns
Phase 4: On-prem Cutover - Switch on-prem VNet to use custom DNS (10.0.10.4)
Phase 5: Hub DNS - Install BIND9 on hub-vm-dns with bidirectional forwarding
Phase 6: Hub Cutover - Switch hub VNet to use custom DNS (10.1.10.4)

End State:
- Both VNets operational with custom BIND9 DNS servers
- Bidirectional DNS forwarding between on-prem and hub
- All VMs using custom DNS (no more Azure DNS)
- Ready for Phase 7 (spoke networks with Azure Private DNS)

Individual phase scripts remain available for granular debugging/testing.

.PARAMETER Location
Azure region for deployment. Default: centralus

.PARAMETER SubscriptionId
Azure subscription ID. If not provided, uses current subscription context.

.PARAMETER SshPublicKeyPath
Path to SSH public key file. If not provided, uses ~/.ssh/id_rsa.pub

.PARAMETER SkipPhaseValidation
Skip per-phase validation checks (speeds up deployment but reduces safety).

.PARAMETER Force
Skip confirmation prompts and deploy immediately.

.EXAMPLE
./phase1-6-deploy.ps1 -Force

.EXAMPLE
./phase1-6-deploy.ps1 -Location "eastus" -SshPublicKeyPath ~/.ssh/dnsmig.pub -Force

.NOTES
Estimated deployment time: 25-35 minutes
#>

param(
    [string]$Location = 'centralus',
    [string]$SubscriptionId,
    [string]$SshPublicKeyPath,
    [switch]$SkipPhaseValidation,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:deploymentStartTime = Get-Date

# Configuration
$OnpremResourceGroupName = 'rg-onprem-dnsmig'
$HubResourceGroupName = 'rg-hub-dnsmig'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Consolidated Phase 1-6: Full DNS Migration Deployment    ║' -ForegroundColor Cyan
Write-Host '║  Infrastructure → DNS Servers → Complete Cutover           ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

Write-Host 'Deployment Overview:' -ForegroundColor Yellow
Write-Host '  Phase 1: Deploy infrastructure (On-prem + Hub)' -ForegroundColor White
Write-Host '  Phase 2: Establish VNet peering' -ForegroundColor White
Write-Host '  Phase 3: Configure on-prem DNS (BIND9)' -ForegroundColor White
Write-Host '  Phase 4: Cutover on-prem to custom DNS' -ForegroundColor White
Write-Host '  Phase 5: Configure hub DNS with forwarding' -ForegroundColor White
Write-Host '  Phase 6: Cutover hub to custom DNS' -ForegroundColor White
Write-Host ''
Write-Host 'Estimated time: 25-35 minutes' -ForegroundColor Yellow
Write-Host ''

if (-not $Force) {
    $confirmation = Read-Host 'Proceed with full deployment? (yes/no)'
    if ($confirmation -ne 'yes') {
        Write-Host 'Deployment cancelled' -ForegroundColor Yellow
        exit 0
    }
}

# ================================================
# PHASE 1: Infrastructure
# ================================================
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 1: Infrastructure Deployment' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase1StartTime = Get-Date

# Validate prerequisites
Write-Host '[1.1] Validating prerequisites...' -ForegroundColor Yellow

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}
Write-Host '  ✓ Azure CLI available' -ForegroundColor Green

# Handle SSH public key
if (-not $SshPublicKeyPath) {
    $commonPaths = @(
        (Join-Path $HOME '.ssh/id_rsa.pub'),
        (Join-Path $HOME '.ssh/dnsmig.pub')
    )
    
    $SshPublicKeyPath = $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $SshPublicKeyPath) {
        Write-Error 'SSH public key not found. Generate with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/dnsmig'
    }
}

if (-not (Test-Path $SshPublicKeyPath)) {
    Write-Error "SSH public key not found at: $SshPublicKeyPath"
}

$sshPublicKey = Get-Content $SshPublicKeyPath -Raw
Write-Host "  ✓ SSH public key loaded: $SshPublicKeyPath" -ForegroundColor Green

# Set subscription
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to set subscription'
    }
}

$currentSub = az account show --query 'name' -o tsv
Write-Host "  ✓ Subscription: $currentSub" -ForegroundColor Green
Write-Host ''

# Deploy via Bicep (Phase 1)
Write-Host '[1.2] Deploying infrastructure (10-15 minutes)...' -ForegroundColor Yellow

$bicepFile = 'bicep/phase1-main.bicep'
if (-not (Test-Path $bicepFile)) {
    Write-Error "Bicep template not found: $bicepFile"
}

$deploymentName = "phase1-6-infra-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployOutput = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $bicepFile `
    --parameters location=$Location `
    --parameters sshPublicKey="$($sshPublicKey.Trim())" `
    --parameters onpremResourceGroupName=$OnpremResourceGroupName `
    --parameters hubResourceGroupName=$HubResourceGroupName `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host $deployOutput -ForegroundColor Red
    Write-Error 'Infrastructure deployment failed'
}

$deployment = $deployOutput | ConvertFrom-Json
$phase1Time = (Get-Date) - $phase1StartTime
Write-Host "  ✓ Infrastructure deployed ($($phase1Time.Minutes)m $($phase1Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# PHASE 2: VNet Peering
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 2: VNet Peering' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase2StartTime = Get-Date

# Get VNet IDs
Write-Host '[2.1] Resolving VNet resources...' -ForegroundColor Yellow

$onpremVnetId = az network vnet show `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vnet' `
    --query 'id' -o tsv 2>$null

$hubVnetId = az network vnet show `
    --resource-group $HubResourceGroupName `
    --name 'hub-vnet' `
    --query 'id' -o tsv 2>$null

if (-not $onpremVnetId -or -not $hubVnetId) {
    Write-Error 'Failed to resolve VNet IDs'
}

Write-Host '  ✓ VNets resolved' -ForegroundColor Green
Write-Host ''

Write-Host '[2.2] Creating VNet peering connections...' -ForegroundColor Yellow

# On-prem to Hub peering
az network vnet peering create `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-to-hub' `
    --vnet-name 'onprem-vnet' `
    --remote-vnet $hubVnetId `
    --allow-vnet-access true `
    --allow-forwarded-traffic true `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to create on-prem to hub peering'
}

# Hub to On-prem peering
az network vnet peering create `
    --resource-group $HubResourceGroupName `
    --name 'hub-to-onprem' `
    --vnet-name 'hub-vnet' `
    --remote-vnet $onpremVnetId `
    --allow-vnet-access true `
    --allow-forwarded-traffic true `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to create hub to on-prem peering'
}

$phase2Time = (Get-Date) - $phase2StartTime
Write-Host "  ✓ VNet peering established ($($phase2Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# PHASE 3: On-prem DNS Configuration
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 3: On-prem DNS Configuration' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase3StartTime = Get-Date

Write-Host '[3.1] Installing BIND9 on onprem-vm-dns...' -ForegroundColor Yellow

$installBindScript = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y bind9 bind9utils bind9-doc dnsutils
sudo systemctl enable bind9
sudo systemctl start bind9
echo "BIND9 installed"
'@

az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts $installBindScript `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to install BIND9 on onprem-vm-dns'
}

Write-Host '  ✓ BIND9 installed' -ForegroundColor Green
Write-Host ''

Write-Host '[3.2] Configuring DNS zones and forwarding...' -ForegroundColor Yellow

# Create onprem.pvt zone file
$onpremZoneFile = @"
;; onprem.pvt zone
;; Auto-generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
`$TTL 300
@       IN      SOA     ns1.onprem.pvt. admin.onprem.pvt. (
                        $(Get-Date -Format 'yyyyMMddHH')  ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL

        IN      NS      ns1.onprem.pvt.
ns1     IN      A       10.0.10.4

;; Host records
dns     IN      A       10.0.10.4
client  IN      A       10.0.10.5
"@

$zoneBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($onpremZoneFile))

$configureOnpremDns = @"
#!/bin/bash
set -e

# Create zone file
echo '$zoneBase64' | base64 -d > /tmp/db.onprem.pvt
sudo mv /tmp/db.onprem.pvt /etc/bind/db.onprem.pvt
sudo chown bind:bind /etc/bind/db.onprem.pvt
sudo chmod 644 /etc/bind/db.onprem.pvt

# Add zone to named.conf.local
if ! grep -q 'zone "onprem.pvt"' /etc/bind/named.conf.local; then
    cat | sudo tee -a /etc/bind/named.conf.local > /dev/null << 'EOFZONE'

zone "onprem.pvt" {
    type master;
    file "/etc/bind/db.onprem.pvt";
    allow-query { any; };
    allow-transfer { none; };
};
EOFZONE
fi

# Configure forwarders (Azure DNS)
if ! grep -q 'forwarders' /etc/bind/named.conf.options; then
    sudo sed -i '/options {/a \        forwarders { 168.63.129.16; };' /etc/bind/named.conf.options
fi

# Validate and reload
sudo named-checkconf
sudo named-checkzone onprem.pvt /etc/bind/db.onprem.pvt
sudo systemctl reload bind9

echo "On-prem DNS configured"
"@

az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts $configureOnpremDns `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to configure on-prem DNS'
}

$phase3Time = (Get-Date) - $phase3StartTime
Write-Host "  ✓ On-prem DNS configured ($($phase3Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# PHASE 4: On-prem DNS Cutover
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 4: On-prem DNS Cutover' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase4StartTime = Get-Date

Write-Host '[4.1] Updating on-prem VNet DNS servers...' -ForegroundColor Yellow

az network vnet update `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vnet' `
    --dns-servers '10.0.10.4' `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to update on-prem VNet DNS'
}

Write-Host '  ✓ VNet DNS updated to 10.0.10.4' -ForegroundColor Green
Write-Host ''

Write-Host '[4.2] Restarting VMs to apply DNS changes...' -ForegroundColor Yellow

az vm restart --resource-group $OnpremResourceGroupName --name 'onprem-vm-dns' --no-wait
az vm restart --resource-group $OnpremResourceGroupName --name 'onprem-vm-client' --no-wait

Start-Sleep -Seconds 45

$phase4Time = (Get-Date) - $phase4StartTime
Write-Host "  ✓ On-prem cutover complete ($($phase4Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# PHASE 5: Hub DNS Configuration
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 5: Hub DNS Configuration' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase5StartTime = Get-Date

Write-Host '[5.1] Installing BIND9 on hub-vm-dns...' -ForegroundColor Yellow

az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts $installBindScript `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to install BIND9 on hub-vm-dns'
}

Write-Host '  ✓ BIND9 installed' -ForegroundColor Green
Write-Host ''

Write-Host '[5.2] Configuring DNS with bidirectional forwarding...' -ForegroundColor Yellow

# Create azure.pvt zone file
$azureZoneFile = @"
;; azure.pvt zone
;; Auto-generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
`$TTL 300
@       IN      SOA     ns1.azure.pvt. admin.azure.pvt. (
                        $(Get-Date -Format 'yyyyMMddHH')  ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL

        IN      NS      ns1.azure.pvt.
ns1     IN      A       10.1.10.4

;; Host records
dns     IN      A       10.1.10.4
app     IN      A       10.1.10.5
"@

$azureZoneBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($azureZoneFile))

$configureHubDns = @"
#!/bin/bash
set -e

# Create zone file
echo '$azureZoneBase64' | base64 -d > /tmp/db.azure.pvt
sudo mv /tmp/db.azure.pvt /etc/bind/db.azure.pvt
sudo chown bind:bind /etc/bind/db.azure.pvt
sudo chmod 644 /etc/bind/db.azure.pvt

# Add zone to named.conf.local
if ! grep -q 'zone "azure.pvt"' /etc/bind/named.conf.local; then
    cat | sudo tee -a /etc/bind/named.conf.local > /dev/null << 'EOFZONE'

zone "azure.pvt" {
    type master;
    file "/etc/bind/db.azure.pvt";
    allow-query { any; };
    allow-transfer { none; };
};
EOFZONE
fi

# Configure conditional forwarding to on-prem DNS
if ! grep -q 'zone "onprem.pvt"' /etc/bind/named.conf.local; then
    cat | sudo tee -a /etc/bind/named.conf.local > /dev/null << 'EOFZONE'

zone "onprem.pvt" {
    type forward;
    forward only;
    forwarders { 10.0.10.4; };
};
EOFZONE
fi

# Add DNSSEC validation exemptions
if ! grep -q 'validate-except' /etc/bind/named.conf.options; then
    sudo sed -i '/dnssec-validation auto;/a \        validate-except { "onprem.pvt."; "azure.pvt."; };' /etc/bind/named.conf.options
fi

# Configure default forwarders (Azure DNS)
if ! grep -q 'forwarders' /etc/bind/named.conf.options; then
    sudo sed -i '/options {/a \        forwarders { 168.63.129.16; };' /etc/bind/named.conf.options
fi

# Validate and reload
sudo named-checkconf
sudo named-checkzone azure.pvt /etc/bind/db.azure.pvt
sudo systemctl reload bind9

echo "Hub DNS configured"
"@

az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts $configureHubDns `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to configure hub DNS'
}

Write-Host ''
Write-Host '[5.3] Updating on-prem DNS to forward to hub...' -ForegroundColor Yellow

$updateOnpremForwarding = @'
#!/bin/bash
set -e

# Add conditional forwarding to hub DNS
if ! grep -q 'zone "azure.pvt"' /etc/bind/named.conf.local; then
    cat | sudo tee -a /etc/bind/named.conf.local > /dev/null << 'EOFZONE'

zone "azure.pvt" {
    type forward;
    forward only;
    forwarders { 10.1.10.4; };
};
EOFZONE
fi

# Add DNSSEC validation exemption
if ! grep -q 'validate-except' /etc/bind/named.conf.options; then
    sudo sed -i '/dnssec-validation auto;/a \        validate-except { "onprem.pvt."; "azure.pvt."; };' /etc/bind/named.conf.options
fi

# Validate and reload
sudo named-checkconf
sudo systemctl reload bind9

echo "Bidirectional forwarding configured"
'@

az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts $updateOnpremForwarding `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to update on-prem forwarding'
}

$phase5Time = (Get-Date) - $phase5StartTime
Write-Host "  ✓ Hub DNS + bidirectional forwarding configured ($($phase5Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# PHASE 6: Hub DNS Cutover
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 6: Hub DNS Cutover' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$phase6StartTime = Get-Date

Write-Host '[6.1] Updating hub VNet DNS servers...' -ForegroundColor Yellow

az network vnet update `
    --resource-group $HubResourceGroupName `
    --name 'hub-vnet' `
    --dns-servers '10.1.10.4' `
    --output none 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to update hub VNet DNS'
}

Write-Host '  ✓ VNet DNS updated to 10.1.10.4' -ForegroundColor Green
Write-Host ''

Write-Host '[6.2] Restarting VMs to apply DNS changes...' -ForegroundColor Yellow

az vm restart --resource-group $HubResourceGroupName --name 'hub-vm-dns' --no-wait
az vm restart --resource-group $HubResourceGroupName --name 'hub-vm-app' --no-wait

Start-Sleep -Seconds 45

$phase6Time = (Get-Date) - $phase6StartTime
Write-Host "  ✓ Hub cutover complete ($($phase6Time.Seconds)s)" -ForegroundColor Green
Write-Host ''

# ================================================
# Deployment Complete
# ================================================
$totalTime = (Get-Date) - $script:deploymentStartTime

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Phase 1-6: Deployment Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''

Write-Host 'Summary:' -ForegroundColor Cyan
Write-Host "  Total Time: $($totalTime.Minutes)m $($totalTime.Seconds)s" -ForegroundColor White
Write-Host "  Phase 1 (Infrastructure):          $($phase1Time.Minutes)m $($phase1Time.Seconds)s" -ForegroundColor White
Write-Host "  Phase 2 (VNet Peering):            $($phase2Time.Seconds)s" -ForegroundColor White
Write-Host "  Phase 3 (On-prem DNS Config):      $($phase3Time.Seconds)s" -ForegroundColor White
Write-Host "  Phase 4 (On-prem Cutover):         $($phase4Time.Seconds)s" -ForegroundColor White
Write-Host "  Phase 5 (Hub DNS Config):          $($phase5Time.Seconds)s" -ForegroundColor White
Write-Host "  Phase 6 (Hub Cutover):             $($phase6Time.Seconds)s" -ForegroundColor White
Write-Host ''

Write-Host 'Current State:' -ForegroundColor Cyan
Write-Host '  ✓ On-prem VNet:        10.0.0.0/16 using DNS 10.0.10.4' -ForegroundColor Green
Write-Host '  ✓ Hub VNet:            10.1.0.0/16 using DNS 10.1.10.4' -ForegroundColor Green
Write-Host '  ✓ VNet Peering:        Bidirectional (on-prem ↔ hub)' -ForegroundColor Green
Write-Host '  ✓ DNS Forwarding:      Bidirectional (onprem.pvt ↔ azure.pvt)' -ForegroundColor Green
Write-Host '  ✓ DNSSEC:              Exemptions for private zones' -ForegroundColor Green
Write-Host ''

Write-Host 'DNS Architecture:' -ForegroundColor Cyan
Write-Host '  On-prem DNS Server:' -ForegroundColor Yellow
Write-Host '    • onprem-vm-dns (10.0.10.4)' -ForegroundColor White
Write-Host '    • Authoritative for: onprem.pvt' -ForegroundColor White
Write-Host '    • Forwards to hub:   azure.pvt → 10.1.10.4' -ForegroundColor White
Write-Host '    • Forwards to Azure: * → 168.63.129.16' -ForegroundColor White
Write-Host ''
Write-Host '  Hub DNS Server:' -ForegroundColor Yellow
Write-Host '    • hub-vm-dns (10.1.10.4)' -ForegroundColor White
Write-Host '    • Authoritative for: azure.pvt' -ForegroundColor White
Write-Host '    • Forwards to on-prem: onprem.pvt → 10.0.10.4' -ForegroundColor White
Write-Host '    • Forwards to Azure: * → 168.63.129.16' -ForegroundColor White
Write-Host ''

Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Validate deployment:' -ForegroundColor White
Write-Host '     ./scripts/phase6-test.ps1' -ForegroundColor Green
Write-Host ''
Write-Host '  2. Verify DNS resolution:' -ForegroundColor White
Write-Host '     • From on-prem: nslookup dns.azure.pvt' -ForegroundColor Gray
Write-Host '     • From hub: nslookup dns.onprem.pvt' -ForegroundColor Gray
Write-Host ''
Write-Host '  3. Continue to Phase 7 (Spoke Networks):' -ForegroundColor White
Write-Host '     ./scripts/phase7-deploy.ps1' -ForegroundColor Green
Write-Host ''

Write-Host 'Individual Phase Scripts:' -ForegroundColor Cyan
Write-Host '  Available for granular testing/debugging:' -ForegroundColor Gray
Write-Host '    • phase1-deploy.ps1, phase2-deploy.ps1, phase3-deploy.ps1' -ForegroundColor Gray
Write-Host '    • phase4-deploy.ps1, phase5-deploy.ps1, phase6-deploy.ps1' -ForegroundColor Gray
Write-Host '    • phase1-test.ps1 through phase6-test.ps1' -ForegroundColor Gray
Write-Host ''

exit 0
