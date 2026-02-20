#!/usr/bin/env pwsh
<#
.SYNOPSIS
Phase 3: Configure On-Prem DNS server (BIND9).

.DESCRIPTION
Installs and configures BIND9 on the on-prem DNS VM:
- Installs BIND9 DNS server
- Configures onprem.pvt authoritative zone
- Adds DNS records for on-prem resources
- Configures forwarding to Azure DNS (168.63.129.16) for internet names
- VNet DNS settings remain unchanged (still using Azure DNS)

The DNS server is configured but not yet active for the VNet.

.PARAMETER OnpremResourceGroupName
On-prem resource group name. Default: rg-onprem-dnsmig

.PARAMETER OnpremDnsVmName
On-prem DNS VM name. Default: onprem-vm-dns

.PARAMETER DnsZone
DNS zone name for on-prem. Default: onprem.pvt

.EXAMPLE
./phase3-deploy.ps1

.EXAMPLE
./phase3-deploy.ps1 -OnpremResourceGroupName "my-onprem-rg"
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig',
    [string]$OnpremDnsVmName = 'onprem-vm-dns',
    [string]$DnsZone = 'onprem.pvt'
)

$ErrorActionPreference = 'Stop'

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 3 - On-Prem DNS Configuration                      ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

# Validate resource group and VM exist
Write-Host '[1/4] Validating environment...' -ForegroundColor Yellow

$rgExists = az group exists --name $OnpremResourceGroupName
if ($rgExists -eq 'false') {
    Write-Error "Resource group '$OnpremResourceGroupName' not found. Have you run Phase 1?"
}
Write-Host "✓ Resource group found: $OnpremResourceGroupName" -ForegroundColor Green

$vm = az vm show --resource-group $OnpremResourceGroupName --name $OnpremDnsVmName 2>$null | ConvertFrom-Json
if (-not $vm) {
    Write-Error "VM '$OnpremDnsVmName' not found in $OnpremResourceGroupName"
}
Write-Host "✓ VM found: $OnpremDnsVmName (IP: $($vm.privateIps))" -ForegroundColor Green

# Install BIND9
Write-Host ''
Write-Host '[2/4] Installing BIND9...' -ForegroundColor Yellow
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
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts $installScript `
    --query 'value[0].message' -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not ($installOutput -like '*SUCCESS*')) {
    Write-Host 'Installation output:' -ForegroundColor Red
    Write-Host $installOutput -ForegroundColor Red
    Write-Error 'BIND9 installation failed'
}

Write-Host '✓ BIND9 installed successfully' -ForegroundColor Green

# Configure BIND9
Write-Host ''
Write-Host '[3/4] Configuring BIND9...' -ForegroundColor Yellow
Write-Host "  Zone: $DnsZone" -ForegroundColor Gray
Write-Host '  Forwarding: Azure DNS (168.63.129.16)' -ForegroundColor Gray

# Create zone file content
$zoneFileContent = @"
`$TTL 300
@       IN      SOA     ns1.$DnsZone. admin.$DnsZone. (
                        2026022001      ; Serial
                        3600            ; Refresh
                        1800            ; Retry
                        604800          ; Expire
                        300 )           ; Minimum TTL

; Name servers
@       IN      NS      ns1.$DnsZone.

; DNS server
ns1     IN      A       10.0.10.4
dns     IN      A       10.0.10.4

; Client VM
client  IN      A       10.0.10.5
"@

# Create named.conf.local content
$namedConfLocal = @"
// On-Prem Private Zone
zone "$DnsZone" {
    type master;
    file "/etc/bind/db.$DnsZone";
    allow-query { any; };
    allow-transfer { none; };
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
    
    // Disable recursion for authoritative queries, enable for forwarding
    recursion yes;
    allow-recursion { any; };
    
    // Forward all non-local queries to Azure DNS
    forwarders {
        168.63.129.16;
    };
    forward only;
    
    // DNSSEC validation
    dnssec-validation auto;
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
base64 -d /tmp/zone.b64 | sudo tee /etc/bind/db.$DnsZone > /dev/null
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
test -f /etc/bind/db.$DnsZone || exit 1
test -f /etc/bind/named.conf.local || exit 1
test -f /etc/bind/named.conf.options || exit 1

echo "Validating configuration..."
sudo /usr/sbin/named-checkconf || sudo /usr/bin/named-checkconf

echo "Validating zone file..."
sudo /usr/sbin/named-checkzone $DnsZone /etc/bind/db.$DnsZone || sudo /usr/bin/named-checkzone $DnsZone /etc/bind/db.$DnsZone

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
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts $configScript `
    --query 'value[0].message' -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not ($configOutput -like '*SUCCESS*')) {
    Write-Host 'Configuration output:' -ForegroundColor Red
    Write-Host $configOutput -ForegroundColor Red
    Write-Error 'BIND9 configuration failed'
}

Write-Host '✓ BIND9 configured successfully' -ForegroundColor Green

# Verify DNS service
Write-Host ''
Write-Host '[4/4] Verifying DNS service...' -ForegroundColor Yellow

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
echo "Test query (dns.$DnsZone):"
/usr/bin/dig @127.0.0.1 +short dns.$DnsZone || sudo /usr/bin/dig @127.0.0.1 +short dns.$DnsZone

echo "SUCCESS"
"@

$verifyOutput = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name $OnpremDnsVmName `
    --command-id RunShellScript `
    --scripts $verifyScript `
    --query 'value[0].message' -o tsv 2>$null

if ($verifyOutput -like '*SUCCESS*') {
    Write-Host '✓ DNS service is running' -ForegroundColor Green
}
else {
    Write-Host '⚠ Could not verify DNS service' -ForegroundColor Yellow
    Write-Host $verifyOutput -ForegroundColor Gray
}

# Summary
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host '✓ Phase 3 Complete: On-Prem DNS Configured' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'DNS Server Details:' -ForegroundColor Cyan
Write-Host '  Server IP: 10.0.10.4' -ForegroundColor White
Write-Host "  Zone: $DnsZone" -ForegroundColor White
Write-Host '  Forwarding: 168.63.129.16 (Azure DNS)' -ForegroundColor White
Write-Host ''
Write-Host 'Important Notes:' -ForegroundColor Yellow
Write-Host '  • DNS server is configured but NOT yet active' -ForegroundColor White
Write-Host '  • VNet still uses Azure DNS (168.63.129.16)' -ForegroundColor White
Write-Host '  • VMs will not use custom DNS until Phase 4 cutover' -ForegroundColor White
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Run validation tests:' -ForegroundColor White
Write-Host '     ./scripts/phase3-test.ps1' -ForegroundColor Green
Write-Host '  2. Test queries directly to DNS server (10.0.10.4)' -ForegroundColor White
Write-Host '  3. Proceed to Phase 4 for DNS cutover' -ForegroundColor White
Write-Host ''

exit 0
