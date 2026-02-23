#!/usr/bin/env pwsh
<#
.SYNOPSIS
Phase 5: Configure Hub DNS server (BIND9) with bidirectional forwarding.

.DESCRIPTION
Installs and configures BIND9 on the hub DNS VM:
- Installs BIND9 DNS server on hub-vm-dns
- Configures azure.pvt authoritative zone
- Adds DNS records for hub resources
- Configures forwarding to on-prem DNS (10.0.10.4) for onprem.pvt zone
- Configures forwarding to Azure DNS (168.63.129.16) for internet names
- Updates on-prem DNS to forward azure.pvt queries to hub DNS (10.1.10.4)
- VNet DNS settings remain unchanged (still using Azure DNS)

The DNS server is configured but not yet active for the VNet.

.PARAMETER HubResourceGroupName
Hub resource group name. Default: rg-hub-dnsmig

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER HubDnsVmName
Hub DNS VM name. Default: hub-vm-dns

.PARAMETER OnpremDnsVmName
On-prem DNS VM name. Default: onprem-vm-dns

.PARAMETER HubDnsZone
DNS zone name for hub. Default: azure.pvt

.PARAMETER OnpremDnsZone
DNS zone name for on-prem. Default: onprem.pvt

.EXAMPLE
./phase5-deploy.ps1

.EXAMPLE
./phase5-deploy.ps1 -HubResourceGroupName "my-hub-rg"
#>

param(
    [string]$HubResourceGroupName = 'rg-hub-dnsmig',
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$HubDnsVmName = 'hub-vm-dns',
    [string]$OnpremDnsVmName = 'onprem-vm-dns',
    [string]$HubDnsZone = 'azure.pvt',
    [string]$OnpremDnsZone = 'onprem.pvt'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 5 - Hub DNS Configuration                          ║' -ForegroundColor Cyan
Write-Host '║  + Bidirectional Forwarding                               ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Validate resource groups and VMs exist
Write-Host '[1/6] Validating environment...' -ForegroundColor Yellow

$hubRgExists = az group exists --name $HubResourceGroupName
if ($hubRgExists -eq 'false') {
    Write-Error "Resource group '$HubResourceGroupName' not found. Have you run Phase 1?"
}
Write-Host "✓ Hub resource group found: $HubResourceGroupName" -ForegroundColor Green

$onpremRgExists = az group exists --name $OnpremResourceGroupName
if ($onpremRgExists -eq 'false') {
    Write-Error "Resource group '$OnpremResourceGroupName' not found. Have you run Phase 1?"
}
Write-Host "✓ On-prem resource group found: $OnpremResourceGroupName" -ForegroundColor Green

$hubVm = az vm show --resource-group $HubResourceGroupName --name $HubDnsVmName 2>$null | ConvertFrom-Json
if (-not $hubVm) {
    Write-Error "VM '$HubDnsVmName' not found in $HubResourceGroupName"
}
Write-Host "✓ Hub VM found: $HubDnsVmName (IP: $($hubVm.privateIps))" -ForegroundColor Green

$onpremVm = az vm show --resource-group $OnpremResourceGroupName --name $OnpremDnsVmName 2>$null | ConvertFrom-Json
if (-not $onpremVm) {
    Write-Error "VM '$OnpremDnsVmName' not found in $OnpremResourceGroupName"
}
Write-Host "✓ On-prem VM found: $OnpremDnsVmName (IP: $($onpremVm.privateIps))" -ForegroundColor Green

# Install BIND9 on Hub
Write-Host ''
Write-Host '[2/6] Installing BIND9 on Hub DNS server...' -ForegroundColor Yellow
Write-Host '  This may take 2-3 minutes...' -ForegroundColor Gray

$installScript = @'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH

echo "Updating package lists..."
sudo apt-get update -qq > /dev/null 2>&1

echo "Installing BIND9..."
sudo apt-get install -y bind9 bind9utils dnsutils > /dev/null 2>&1

# Verify installation with absolute paths
test -x /usr/sbin/named-checkconf || test -x /usr/bin/named-checkconf || exit 1
test -x /usr/sbin/named-checkzone || test -x /usr/bin/named-checkzone || exit 1
test -x /usr/bin/dig || exit 1

echo "BIND9 installation complete"
sudo systemctl enable named 2>/dev/null || true
echo "SUCCESS"
'@

$installOutput = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts $installScript `
    --query 'value[0].message' -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not ($installOutput -like '*SUCCESS*')) {
    Write-Host 'Installation output:' -ForegroundColor Red
    Write-Host $installOutput -ForegroundColor Red
    Write-Error 'BIND9 installation failed on Hub'
}

Write-Host '✓ BIND9 installed successfully on Hub' -ForegroundColor Green

# Configure BIND9 on Hub
Write-Host ''
Write-Host '[3/6] Configuring BIND9 on Hub...' -ForegroundColor Yellow
Write-Host "  Zone: $HubDnsZone" -ForegroundColor Gray
Write-Host "  Forwarding: $OnpremDnsZone -> 10.0.10.4" -ForegroundColor Gray
Write-Host '  Forwarding: Internet -> 168.63.129.16 (Azure DNS)' -ForegroundColor Gray

# Create zone file content for azure.pvt
$zoneFileContent = @"
`$TTL 300
@       IN      SOA     ns1.$HubDnsZone. admin.$HubDnsZone. (
                        2026022201      ; Serial
                        3600            ; Refresh
                        1800            ; Retry
                        604800          ; Expire
                        300 )           ; Minimum TTL

; Name servers
@       IN      NS      ns1.$HubDnsZone.

; DNS server
ns1     IN      A       10.1.10.4
dns     IN      A       10.1.10.4

; Client VM
client  IN      A       10.1.10.5
"@

# Create named.conf.local content with azure.pvt zone and onprem.pvt forwarding
$namedConfLocal = @"
// Hub (Azure) Private Zone
zone "$HubDnsZone" {
    type master;
    file "/etc/bind/db.$HubDnsZone";
    allow-query { any; };
    allow-transfer { none; };
};

// Forward on-prem zone to on-prem DNS server
zone "$OnpremDnsZone" {
    type forward;
    forward only;
    forwarders { 10.0.10.4; };
};
"@

# Create named.conf.options content
$namedConfOptions = @'
options {
    directory "/var/cache/bind";
    
    // Listen on all interfaces
    listen-on { any; };
    listen-on-v6 { none; };
    
    // Allow queries from any source
    allow-query { any; };
    
    // Enable recursion for forwarding
    recursion yes;
    allow-recursion { any; };
    
    // Forward all non-local queries to Azure DNS
    forwarders {
        168.63.129.16;
    };
    forward only;
    
    // DNSSEC validation (exempt private zones)
    dnssec-validation auto;
    validate-except { "onprem.pvt"; };
};
'@

# Encode to base64
$zoneFileBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($zoneFileContent))
$namedConfLocalBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($namedConfLocal))
$namedConfOptionsBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($namedConfOptions))

# Configuration script using base64 encoding
$configScript = @"
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH

echo "Writing zone file..."
echo '$zoneFileBase64' > /tmp/zone.b64
base64 -d /tmp/zone.b64 | sudo tee /etc/bind/db.$HubDnsZone > /dev/null
rm /tmp/zone.b64

echo "Writing named.conf.local..."
echo '$namedConfLocalBase64' > /tmp/local.b64
base64 -d /tmp/local.b64 | sudo tee /etc/bind/named.conf.local > /dev/null
rm /tmp/local.b64

echo "Writing named.conf.options..."
echo '$namedConfOptionsBase64' > /tmp/options.b64
base64 -d /tmp/options.b64 | sudo tee /etc/bind/named.conf.options > /dev/null
rm /tmp/options.b64

# Verify all files exist
test -f /etc/bind/db.$HubDnsZone || exit 1
test -f /etc/bind/named.conf.local || exit 1
test -f /etc/bind/named.conf.options || exit 1

echo "Validating configuration..."
sudo /usr/sbin/named-checkconf || sudo /usr/bin/named-checkconf

echo "Validating zone file..."
sudo /usr/sbin/named-checkzone $HubDnsZone /etc/bind/db.$HubDnsZone || sudo /usr/bin/named-checkzone $HubDnsZone /etc/bind/db.$HubDnsZone

echo "Restarting BIND9..."
sudo systemctl restart named

# Wait for BIND to start
sleep 2

if ! systemctl is-active --quiet named; then
    echo "ERROR: BIND9 failed to start"
    sudo systemctl status named --no-pager
    exit 1
fi

echo "Configuration complete"
echo "SUCCESS"
"@

$configOutput = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts $configScript `
    --query 'value[0].message' -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not ($configOutput -like '*SUCCESS*')) {
    Write-Host 'Configuration output:' -ForegroundColor Red
    Write-Host $configOutput -ForegroundColor Red
    Write-Error 'BIND9 configuration failed on Hub'
}

Write-Host '✓ BIND9 configured successfully on Hub' -ForegroundColor Green

# Verify Hub DNS service
Write-Host ''
Write-Host '[4/6] Verifying Hub DNS service...' -ForegroundColor Yellow

$verifyScript = @"
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH

echo "Service status:"
systemctl status named --no-pager | grep "Active:" || true

echo ""
echo "Listening ports:"
ss -tulnp | grep named || true

echo ""
echo "Test query (dns.$HubDnsZone):"
/usr/bin/dig @127.0.0.1 +short dns.$HubDnsZone || sudo /usr/bin/dig @127.0.0.1 +short dns.$HubDnsZone

echo "SUCCESS"
"@

$verifyOutput = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts $verifyScript `
    --query 'value[0].message' -o tsv 2>$null

if ($verifyOutput -like '*SUCCESS*') {
    Write-Host '✓ Hub DNS service is running' -ForegroundColor Green
}
else {
    Write-Host '⚠ Could not verify Hub DNS service' -ForegroundColor Yellow
    Write-Host $verifyOutput -ForegroundColor Gray
}

# Update On-Prem DNS to forward azure.pvt to Hub
Write-Host ''
Write-Host '[5/6] Configuring bidirectional forwarding...' -ForegroundColor Yellow
Write-Host "  Updating On-Prem DNS to forward $HubDnsZone -> 10.1.10.4" -ForegroundColor Gray

# Read current on-prem named.conf.local and add azure.pvt forwarding zone
$updateOnpremConfLocal = @"
// On-Prem Private Zone
zone "$OnpremDnsZone" {
    type master;
    file "/etc/bind/db.$OnpremDnsZone";
    allow-query { any; };
    allow-transfer { none; };
};

// Forward hub (azure) zone to hub DNS server
zone "$HubDnsZone" {
    type forward;
    forward only;
    forwarders { 10.1.10.4; };
};
"@

# Update on-prem named.conf.options to exempt azure.pvt from DNSSEC validation
$updateOnpremConfOptions = @'
options {
    directory "/var/cache/bind";
    
    // Listen on all interfaces
    listen-on { any; };
    listen-on-v6 { none; };
    
    // Allow queries from any source
    allow-query { any; };
    
    // Disable recursion for authoritative queries, enable for forwarding
    recursion yes;
    allow-recursion { any; };
    
    // Forward all non-local queries to Azure DNS
    forwarders {
        168.63.129.16;
    };
    forward only;
    
    // DNSSEC validation (exempt private zones)
    dnssec-validation auto;
    validate-except { "azure.pvt"; };
};
'@

$updateOnpremConfLocalBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($updateOnpremConfLocal))
$updateOnpremConfOptionsBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($updateOnpremConfOptions))

$updateOnpremScript = @"
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH

echo "Updating named.conf.local on On-Prem DNS..."
echo '$updateOnpremConfLocalBase64' > /tmp/local.b64
base64 -d /tmp/local.b64 | sudo tee /etc/bind/named.conf.local > /dev/null
rm /tmp/local.b64

echo "Updating named.conf.options on On-Prem DNS..."
echo '$updateOnpremConfOptionsBase64' > /tmp/options.b64
base64 -d /tmp/options.b64 | sudo tee /etc/bind/named.conf.options > /dev/null
rm /tmp/options.b64

echo "Validating configuration..."
sudo /usr/sbin/named-checkconf || sudo /usr/bin/named-checkconf

echo "Restarting BIND9..."
sudo systemctl restart named

# Wait for BIND to start
sleep 2

if ! systemctl is-active --quiet named; then
    echo "ERROR: BIND9 failed to start"
    sudo systemctl status named --no-pager
    exit 1
fi

echo "On-Prem DNS updated successfully"
echo "SUCCESS"
"@

$updateOnpremOutput = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts $updateOnpremScript `
    --query 'value[0].message' -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not ($updateOnpremOutput -like '*SUCCESS*')) {
    Write-Host 'Update output:' -ForegroundColor Red
    Write-Host $updateOnpremOutput -ForegroundColor Red
    Write-Error 'Failed to update On-Prem DNS with bidirectional forwarding'
}

Write-Host '✓ Bidirectional forwarding configured' -ForegroundColor Green

# Verify bidirectional forwarding
Write-Host ''
Write-Host '[6/6] Verifying bidirectional forwarding...' -ForegroundColor Yellow

Write-Host "  Testing Hub -> On-Prem ($HubDnsZone -> $OnpremDnsZone)..." -ForegroundColor Gray
$hubToOnpremTest = az vm run-command invoke `
    --resource-group $HubResourceGroupName `
    --name $HubDnsVmName `
    --command-id RunShellScript `
    --scripts "dig @127.0.0.1 +short dns.$OnpremDnsZone 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

if ($hubToOnpremTest -like '*10.0.10.4*') {
    Write-Host "  ✓ Hub can resolve $OnpremDnsZone records" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ Hub forward test result: $hubToOnpremTest" -ForegroundColor Yellow
}

Write-Host "  Testing On-Prem -> Hub ($OnpremDnsZone -> $HubDnsZone)..." -ForegroundColor Gray
$onpremToHubTest = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts "dig @127.0.0.1 +short dns.$HubDnsZone 2>&1" `
    --query 'value[0].message' -o tsv 2>$null

if ($onpremToHubTest -like '*10.1.10.4*') {
    Write-Host "  ✓ On-Prem can resolve $HubDnsZone records" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ On-Prem forward test result: $onpremToHubTest" -ForegroundColor Yellow
}

# Summary
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host '✓ Phase 5 Complete: Hub DNS + Bidirectional Forwarding' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'DNS Server Configuration:' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Hub DNS Server:' -ForegroundColor White
Write-Host '    IP: 10.1.10.4' -ForegroundColor Gray
Write-Host "    Zone: $HubDnsZone (authoritative)" -ForegroundColor Gray
Write-Host "    Forwards: $OnpremDnsZone -> 10.0.10.4" -ForegroundColor Gray
Write-Host '    Forwards: Internet -> 168.63.129.16' -ForegroundColor Gray
Write-Host ''
Write-Host '  On-Prem DNS Server:' -ForegroundColor White
Write-Host '    IP: 10.0.10.4' -ForegroundColor Gray
Write-Host "    Zone: $OnpremDnsZone (authoritative)" -ForegroundColor Gray
Write-Host "    Forwards: $HubDnsZone -> 10.1.10.4" -ForegroundColor Gray
Write-Host '    Forwards: Internet -> 168.63.129.16' -ForegroundColor Gray
Write-Host ''
Write-Host 'Important Notes:' -ForegroundColor Yellow
Write-Host '  • Both DNS servers are configured but NOT yet active' -ForegroundColor White
Write-Host '  • VNets still use Azure DNS (168.63.129.16)' -ForegroundColor White
Write-Host '  • On-Prem VNet uses custom DNS after Phase 4 (10.0.10.4)' -ForegroundColor White
Write-Host '  • Hub VNet will use custom DNS after Phase 6 cutover' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Run validation tests:' -ForegroundColor White
Write-Host '     ./scripts/phase5-test.ps1' -ForegroundColor Green
Write-Host '  2. Verify bidirectional DNS resolution' -ForegroundColor White
Write-Host '  3. Proceed to Phase 6 for Hub DNS cutover' -ForegroundColor White
Write-Host ''

exit 0
