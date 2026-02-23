#!/usr/bin/env pwsh
<#
.SYNOPSIS
Phase 7: Deploy spoke networks, storage accounts, and configure DNS.

.DESCRIPTION
This phase:
1. Deploys Spoke1 and Spoke2 VNets with VMs
2. Creates storage accounts with private endpoints
3. Establishes VNet peering (Hub <-> Spokes)
4. Auto-generates privatelink DNS records from private endpoint IPs
5. Configures hub-vm-dns with privatelink.blob.core.windows.net zone

.PARAMETER Location
Azure region. Default: centralus

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER Spoke1ResourceGroupName
Spoke1 resource group name. Default: rg-spoke1-dnsmig

.PARAMETER Spoke2ResourceGroupName
Spoke2 resource group name. Default: rg-spoke2-dnsmig

.PARAMETER SshPublicKeyPath
Path to SSH public key. Default: ~/.ssh/id_rsa.pub

.EXAMPLE
./scripts/phase7-deploy.ps1
#>

param(
    [string]$Location = 'centralus',
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$Spoke1ResourceGroupName = 'rg-spoke1-dnsmig',
    [string]$Spoke2ResourceGroupName = 'rg-spoke2-dnsmig',
    [string]$SshPublicKeyPath = '~/.ssh/id_rsa.pub'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 7 - Spoke Networks & Storage                       ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Verify logged in
Write-Host 'Checking Azure CLI login status...' -ForegroundColor Cyan
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error 'Not logged in to Azure CLI. Run: az login'
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "  ✓ Subscription: $($account.name)" -ForegroundColor Green
Write-Host ''

# Validate SSH key
# Expand tilde to home directory if present
if ($SshPublicKeyPath -match '^~') {
    $SshPublicKeyPath = $SshPublicKeyPath -replace '^~', $HOME
}
$resolvedKeyPath = [System.IO.Path]::GetFullPath($SshPublicKeyPath)
if (-not (Test-Path $resolvedKeyPath)) {
    Write-Error "SSH public key not found: $resolvedKeyPath"
}
$sshPublicKey = Get-Content $resolvedKeyPath -Raw
Write-Host "  ✓ SSH public key loaded from: $resolvedKeyPath" -ForegroundColor Green
Write-Host ''

# ================================================
# STEP 1: Deploy Spoke Infrastructure
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'STEP 1: Deploy Spoke Infrastructure' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$bicepFile = 'bicep/phase7-main.bicep'

Write-Host 'Validating Bicep template...' -ForegroundColor Cyan
az bicep build --file $bicepFile 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Bicep validation failed'
}
Write-Host '  ✓ Bicep template is valid' -ForegroundColor Green
Write-Host ''

Write-Host 'Deploying spoke infrastructure (this will take 5-10 minutes)...' -ForegroundColor Cyan
Write-Host '  - Creating resource groups' -ForegroundColor Gray
Write-Host '  - Deploying Spoke1 VNet, VM, Storage, Private Endpoint' -ForegroundColor Gray
Write-Host '  - Deploying Spoke2 VNet, VM, Storage, Private Endpoint' -ForegroundColor Gray
Write-Host ''

$deploymentName = "phase7-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deploymentOutput = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $bicepFile `
    --parameters `
    location=$Location `
    sshPublicKey="$sshPublicKey" `
    spoke1ResourceGroupName=$Spoke1ResourceGroupName `
    spoke2ResourceGroupName=$Spoke2ResourceGroupName `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host 'Deployment failed with output:' -ForegroundColor Red
    Write-Host $deploymentOutput -ForegroundColor Yellow
    Write-Error 'Spoke infrastructure deployment failed'
}

$deployment = $deploymentOutput | ConvertFrom-Json -ErrorAction Stop

Write-Host '  ✓ Spoke infrastructure deployed' -ForegroundColor Green
Write-Host ''

# Extract outputs
$outputs = $deployment.properties.outputs
$spoke1VnetName = $outputs.spoke1VnetName.value
$spoke1VnetId = $outputs.spoke1VnetId.value
$spoke1StorageAccountName = $outputs.spoke1StorageAccountName.value
$spoke1NicId = $outputs.spoke1PrivateEndpointNicId.value

$spoke2VnetName = $outputs.spoke2VnetName.value
$spoke2VnetId = $outputs.spoke2VnetId.value
$spoke2StorageAccountName = $outputs.spoke2StorageAccountName.value
$spoke2NicId = $outputs.spoke2PrivateEndpointNicId.value

Write-Host 'Deployment outputs:' -ForegroundColor Cyan
Write-Host "  Spoke1 VNet: $spoke1VnetName" -ForegroundColor Gray
Write-Host "  Spoke1 Storage: $spoke1StorageAccountName" -ForegroundColor Gray
Write-Host "  Spoke2 VNet: $spoke2VnetName" -ForegroundColor Gray
Write-Host "  Spoke2 Storage: $spoke2StorageAccountName" -ForegroundColor Gray
Write-Host ''

# ================================================
# STEP 2: Create VNet Peering
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'STEP 2: Create VNet Peering' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$hubVnetId = az network vnet show `
    --resource-group $HubResourceGroupName `
    --name 'hub-vnet' `
    --query 'id' -o tsv

Write-Host 'Creating Hub <-> Spoke1 peering...' -ForegroundColor Cyan
az network vnet peering create `
    --resource-group $HubResourceGroupName `
    --name 'hub-to-spoke1' `
    --vnet-name 'hub-vnet' `
    --remote-vnet $spoke1VnetId `
    --allow-vnet-access `
    --allow-forwarded-traffic `
    --output none 2>$null

az network vnet peering create `
    --resource-group $Spoke1ResourceGroupName `
    --name 'spoke1-to-hub' `
    --vnet-name $spoke1VnetName `
    --remote-vnet $hubVnetId `
    --allow-vnet-access `
    --allow-forwarded-traffic `
    --output none 2>$null

Write-Host '  ✓ Hub <-> Spoke1 peering created' -ForegroundColor Green

Write-Host 'Creating Hub <-> Spoke2 peering...' -ForegroundColor Cyan
az network vnet peering create `
    --resource-group $HubResourceGroupName `
    --name 'hub-to-spoke2' `
    --vnet-name 'hub-vnet' `
    --remote-vnet $spoke2VnetId `
    --allow-vnet-access `
    --allow-forwarded-traffic `
    --output none 2>$null

az network vnet peering create `
    --resource-group $Spoke2ResourceGroupName `
    --name 'spoke2-to-hub' `
    --vnet-name $spoke2VnetName `
    --remote-vnet $hubVnetId `
    --allow-vnet-access `
    --allow-forwarded-traffic `
    --output none 2>$null

Write-Host '  ✓ Hub <-> Spoke2 peering created' -ForegroundColor Green
Write-Host ''

# ================================================
# STEP 3: Extract Private Endpoint IPs
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'STEP 3: Extract Private Endpoint IPs' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

Write-Host 'Querying private endpoint IP addresses...' -ForegroundColor Cyan

$spoke1NicInfo = az network nic show --ids $spoke1NicId --query 'ipConfigurations[0].privateIPAddress' -o tsv
$spoke2NicInfo = az network nic show --ids $spoke2NicId --query 'ipConfigurations[0].privateIPAddress' -o tsv

Write-Host "  Spoke1 Storage Private IP: $spoke1NicInfo" -ForegroundColor Gray
Write-Host "  Spoke2 Storage Private IP: $spoke2NicInfo" -ForegroundColor Gray
Write-Host ''

# ================================================
# STEP 4: Generate BIND DNS Zone Configuration
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'STEP 4: Configure DNS for Private Endpoints' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

Write-Host 'Generating DNS zone configurations...' -ForegroundColor Cyan

# Generate privatelink zone file (actual A records)
$privatelinkZoneFile = @"
;; privatelink.blob.core.windows.net zone
;; Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
\$TTL 300
@       IN      SOA     ns1.privatelink.blob.core.windows.net. admin.privatelink.blob.core.windows.net. (
                        $(Get-Date -Format 'yyyyMMddHH')  ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL

        IN      NS      ns1.privatelink.blob.core.windows.net.
ns1     IN      A       10.1.10.4

;; Private Endpoint Records
$spoke1StorageAccountName   IN      A       $spoke1NicInfo
$spoke2StorageAccountName   IN      A       $spoke2NicInfo
"@

# Generate blob.core.windows.net zone file (CNAMEs to privatelink)
$blobZoneFile = @"
;; blob.core.windows.net zone (partial - only private endpoints)
;; Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
\$TTL 300
@       IN      SOA     ns1.blob.core.windows.net. admin.blob.core.windows.net. (
                        $(Get-Date -Format 'yyyyMMddHH')  ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL

        IN      NS      ns1.blob.core.windows.net.
ns1     IN      A       10.1.10.4

;; CNAME records pointing to privatelink zone
$spoke1StorageAccountName   IN      CNAME   $spoke1StorageAccountName.privatelink.blob.core.windows.net.
$spoke2StorageAccountName   IN      CNAME   $spoke2StorageAccountName.privatelink.blob.core.windows.net.
"@

Write-Host '  ✓ Zone files generated' -ForegroundColor Green
Write-Host ''

# ================================================
# STEP 5: Deploy DNS Configuration to Hub
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'STEP 5: Deploy DNS Configuration to Hub DNS Server' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Create zone files on DNS server
Write-Host 'Creating zone files on hub-vm-dns...' -ForegroundColor Cyan

# Use base64 encoding to safely transfer the files
$privatelinkZoneBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($privatelinkZoneFile))
$blobZoneBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($blobZoneFile))

$createZoneScript = @"
#!/bin/bash
set -e

# Decode and write privatelink zone file
echo '$privatelinkZoneBase64' | base64 -d > /tmp/db.privatelink.blob.core.windows.net
sudo mv /tmp/db.privatelink.blob.core.windows.net /etc/bind/db.privatelink.blob.core.windows.net
sudo chown bind:bind /etc/bind/db.privatelink.blob.core.windows.net
sudo chmod 644 /etc/bind/db.privatelink.blob.core.windows.net

# Decode and write blob zone file
echo '$blobZoneBase64' | base64 -d > /tmp/db.blob.core.windows.net
sudo mv /tmp/db.blob.core.windows.net /etc/bind/db.blob.core.windows.net
sudo chown bind:bind /etc/bind/db.blob.core.windows.net
sudo chmod 644 /etc/bind/db.blob.core.windows.net

echo "Zone files created"
"@

az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts $createZoneScript `
    --output none 2>$null

Write-Host '  ✓ Zone files deployed' -ForegroundColor Green

# Update named.conf.local to include both zones
Write-Host 'Updating named.conf.local...' -ForegroundColor Cyan

$namedConfUpdate = @'
#!/bin/bash
set -e

# Check if zones already exist
if grep -q "zone \"blob.core.windows.net\"" /etc/bind/named.conf.local; then
    echo "Zones already configured"
    exit 0
fi

# Append zone configurations
cat >> /etc/bind/named.conf.local << 'EOFZONE'

// Blob Storage Zone (Legacy - covers public FQDNs with CNAMEs to privatelink)
zone "blob.core.windows.net" {
    type master;
    file "/etc/bind/db.blob.core.windows.net";
    allow-query { any; };
    allow-transfer { none; };
};

// Private Link Zone (Legacy - contains A records for private endpoints)
zone "privatelink.blob.core.windows.net" {
    type master;
    file "/etc/bind/db.privatelink.blob.core.windows.net";
    allow-query { any; };
    allow-transfer { none; };
};
EOFZONE

echo "Zone configurations added"
'@

az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts $namedConfUpdate `
    --output none 2>$null

Write-Host '  ✓ named.conf.local updated' -ForegroundColor Green

# Validate configuration and reload
Write-Host 'Validating and reloading BIND9...' -ForegroundColor Cyan

$reloadScript = @'
#!/bin/bash
set -e

# Validate configuration
sudo named-checkconf

# Validate zone files
sudo named-checkzone blob.core.windows.net /etc/bind/db.blob.core.windows.net
sudo named-checkzone privatelink.blob.core.windows.net /etc/bind/db.privatelink.blob.core.windows.net

# Reload BIND9
sudo systemctl reload bind9

# Verify service is running
sudo systemctl status bind9 --no-pager | head -10

echo ""
echo "BIND9 reloaded successfully"
'@

$reloadOutput = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name 'hub-vm-dns' `
    --command-id RunShellScript `
    --scripts $reloadScript `
    --query 'value[0].message' -o tsv 2>$null

if ($reloadOutput -match 'successfully') {
    Write-Host '  ✓ BIND9 configuration validated and reloaded' -ForegroundColor Green
}
else {
    Write-Host '  ⚠ BIND9 reload may have issues. Check output:' -ForegroundColor Yellow
    Write-Host $reloadOutput -ForegroundColor Gray
}

Write-Host ''

# ================================================
# Summary
# ================================================
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Phase 7 Deployment Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'Resources deployed:' -ForegroundColor Cyan
Write-Host "  ✓ Spoke1 VNet: $spoke1VnetName" -ForegroundColor Green
Write-Host "  ✓ Spoke1 Storage: $spoke1StorageAccountName" -ForegroundColor Green
Write-Host "  ✓ Spoke2 VNet: $spoke2VnetName" -ForegroundColor Green
Write-Host "  ✓ Spoke2 Storage: $spoke2StorageAccountName" -ForegroundColor Green
Write-Host '  ✓ VNet peering: Hub <-> Spoke1, Hub <-> Spoke2' -ForegroundColor Green
Write-Host '  ✓ DNS zones: blob.core.windows.net, privatelink.blob.core.windows.net' -ForegroundColor Green
Write-Host ''
Write-Host 'DNS Architecture:' -ForegroundColor Cyan
Write-Host "  - $spoke1StorageAccountName.blob.core.windows.net → CNAME → privatelink → $spoke1NicInfo" -ForegroundColor Gray
Write-Host "  - $spoke2StorageAccountName.blob.core.windows.net → CNAME → privatelink → $spoke2NicInfo" -ForegroundColor Gray
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. Run validation: ./scripts/phase7-test.ps1' -ForegroundColor White
Write-Host '  2. Proceed to Phase 8: Azure Private DNS + Resolver' -ForegroundColor White
Write-Host ''

exit 0
