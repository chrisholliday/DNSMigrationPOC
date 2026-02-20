#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploys Phase 1.2 - Configure on-prem DNS VM and VNet DNS settings.

.DESCRIPTION
- Installs and configures BIND on the on-prem DNS VM
- Creates the onprem.pvt zone and basic host records
- Sets VNet DNS servers to the DNS VM private IP

.PARAMETER ResourceGroupName
Resource group name. Default: rg-onprem-dnsmig

.PARAMETER VnetName
VNet name. Default: onprem-vnet

.PARAMETER DnsVmName
DNS VM name. Default: onprem-vm-dns

.PARAMETER ClientVmName
Client VM name. Default: onprem-vm-client

.PARAMETER ZoneName
DNS zone to create. Default: onprem.pvt

.PARAMETER ForwarderIp
Upstream DNS forwarder IP. Default: 168.63.129.16 (Azure DNS)

.PARAMETER Force
Skip confirmation prompts and deploy immediately.

.EXAMPLE
./phase1-2-deploy.ps1 -Force
#>

param(
    [string]$ResourceGroupName = 'rg-onprem-dnsmig',
    [string]$VnetName = 'onprem-vnet',
    [string]$DnsVmName = 'onprem-vm-dns',
    [string]$ClientVmName = 'onprem-vm-client',
    [string]$ZoneName = 'onprem.pvt',
    [string]$ForwarderIp = '168.63.129.16',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:deploymentStartTime = Get-Date

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '║  Phase 1.2 Deployment - On-Prem DNS Configuration         ║' -ForegroundColor Cyan
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI not found. Please install: https://aka.ms/azure-cli'
}

$rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
if (-not $rgExists) {
    Write-Error "Resource group not found: $ResourceGroupName"
}

if (-not $Force) {
    Write-Host "This will configure $DnsVmName and set VNet DNS for $VnetName." -ForegroundColor Yellow
    $confirmation = Read-Host 'Proceed? (yes/no)'
    if ($confirmation -ne 'yes') {
        Write-Host 'Deployment cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ''
Write-Host '[1/4] Resolving VM private IPs...' -ForegroundColor Yellow

$dnsVmIp = az vm show -d --resource-group $ResourceGroupName --name $DnsVmName --query 'privateIps' -o tsv
if (-not $dnsVmIp) {
    Write-Error "Failed to resolve private IP for $DnsVmName"
}

$clientVmIp = az vm show -d --resource-group $ResourceGroupName --name $ClientVmName --query 'privateIps' -o tsv
if (-not $clientVmIp) {
    Write-Error "Failed to resolve private IP for $ClientVmName"
}

Write-Host "✓ $DnsVmName IP: $dnsVmIp" -ForegroundColor Green
Write-Host "✓ $ClientVmName IP: $clientVmIp" -ForegroundColor Green

Write-Host ''
Write-Host ''
Write-Host '[2/4] Configuring BIND on DNS VM...' -ForegroundColor Yellow

$serial = Get-Date -Format 'yyyyMMdd01'

# Prepare config content in PowerShell (clean, readable)
$zoneFileContent = @"
`$TTL 3600
@   IN SOA ns1.$ZoneName. admin.$ZoneName. (
                $serial ; serial
                3600 ; refresh
                900 ; retry
                604800 ; expire
                86400 ) ; minimum
@   IN NS ns1.$ZoneName.
ns1 IN A $dnsVmIp
dns IN A $dnsVmIp
client IN A $clientVmIp

"@

$bindOptionsContent = @"
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { any; };
    listen-on { 127.0.0.1; $dnsVmIp; };
    listen-on-v6 { none; };
    forwarders { $ForwarderIp; };
    dnssec-validation no;
};

"@

$bindLocalContent = @"
zone "$ZoneName" {
  type master;
  file "/etc/bind/db.$ZoneName";
};

"@

# Convert to base64 once in PowerShell
$zoneFileB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($zoneFileContent))
$bindOptionsB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bindOptionsContent))
$bindLocalB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bindLocalContent))

# Install BIND
$installScript = @'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
sudo apt-get update
sudo apt-get install -y bind9 bind9utils dnsutils
# Verify installation with absolute paths
test -x /usr/sbin/named-checkconf || test -x /usr/bin/named-checkconf || exit 1
test -x /usr/sbin/named-checkzone || test -x /usr/bin/named-checkzone || exit 1
test -x /usr/bin/dig || exit 1
echo "BIND installation complete"
'@

Write-Host '  Installing BIND9...' -ForegroundColor Cyan
$installOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts $installScript `
    --query 'value[0].message' -o tsv

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installation output: $installOutput" -ForegroundColor Red
    Write-Error "BIND installation failed on $DnsVmName"
}

# Check for success marker - use simpler contains check
if (-not ($installOutput -like '*BIND installation complete*')) {
    Write-Host "  Installation output: $installOutput" -ForegroundColor Red
    Write-Error 'BIND installation did not complete successfully'
}

Write-Host '  ✓ BIND9 installed' -ForegroundColor Green

# Write BIND config files using base64 via temp files (most reliable approach)
# This avoids: 1) escaping issues with heredocs, 2) long command-line arguments
Write-Host '  Writing BIND configuration files...' -ForegroundColor Cyan

# Single script that writes all three config files from base64
$configScript = @"
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH

# Write named.conf.options
echo '$bindOptionsB64' > /tmp/options.b64
base64 -d /tmp/options.b64 | sudo tee /etc/bind/named.conf.options > /dev/null
rm /tmp/options.b64

# Write named.conf.local  
echo '$bindLocalB64' > /tmp/local.b64
base64 -d /tmp/local.b64 | sudo tee /etc/bind/named.conf.local > /dev/null
rm /tmp/local.b64

# Write zone file
echo '$zoneFileB64' > /tmp/zone.b64
base64 -d /tmp/zone.b64 | sudo tee /etc/bind/db.$ZoneName > /dev/null
rm /tmp/zone.b64

# Verify all files exist
test -f /etc/bind/named.conf.options || exit 1
test -f /etc/bind/named.conf.local || exit 1
test -f /etc/bind/db.$ZoneName || exit 1

echo 'All configuration files written successfully'
"@

$configOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts $configScript `
    --query 'value[0].message' -o tsv

if ($LASTEXITCODE -ne 0 -or -not ($configOutput -like '*successfully*')) {
    Write-Host "  Config output: $configOutput" -ForegroundColor Red
    Write-Error 'Failed to write BIND configuration files'
}

Write-Host '  ✓ Configuration files written' -ForegroundColor Green

# Validate, restart, and test DNS resolution
Write-Host '  Validating BIND configuration and starting service...' -ForegroundColor Cyan
$validateScript = @"
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:`$PATH
echo "Running named-checkconf..."
sudo /usr/sbin/named-checkconf || sudo /usr/bin/named-checkconf
echo "Running named-checkzone..."
sudo /usr/sbin/named-checkzone $ZoneName /etc/bind/db.$ZoneName || sudo /usr/bin/named-checkzone $ZoneName /etc/bind/db.$ZoneName
echo "Enabling named service..."
# Enable named (redirect stderr as it's just informational)
sudo systemctl enable named 2>/dev/null || true
echo "Restarting named service..."
sudo systemctl restart named
# Wait for BIND to fully start and load zones
sleep 3
# Reload zones to ensure they're active
echo "Reloading zones..."
sudo /usr/sbin/rndc reload || sudo /usr/bin/rndc reload
sleep 2
# Test DNS resolution - this is our success criteria
echo "Testing DNS resolution..."
/usr/bin/dig @127.0.0.1 +short dns.$ZoneName
"@

$validateOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts $validateScript `
    --query 'value[0].message' -o tsv

if ($LASTEXITCODE -ne 0) {
    Write-Host '  ✗ Validation failed' -ForegroundColor Red
    Write-Host '  Full output:' -ForegroundColor Yellow
    Write-Host $validateOutput
    Write-Error "BIND configuration failed on $DnsVmName"
}

# Check if DNS resolution worked by looking for an IP address in the output
if ($validateOutput -match '10\.0\.10\.4') {
    Write-Host '✓ DNS VM configured with BIND and zone file' -ForegroundColor Green
    Write-Host '✓ DNS VM responds for local zone queries' -ForegroundColor Green
}
else {
    Write-Error "DNS validation failed - expected 10.0.10.4 in output. Got: $validateOutput"
}

Write-Host ''
Write-Host '[3/4] Updating VNet DNS servers...' -ForegroundColor Yellow

az network vnet update `
    --resource-group $ResourceGroupName `
    --name $VnetName `
    --dns-servers $dnsVmIp | Out-Null

Write-Host "✓ VNet DNS set to $dnsVmIp" -ForegroundColor Green

Write-Host ''
Write-Host '[4/4] Rebooting VMs to apply DNS settings...' -ForegroundColor Yellow

# Restart DNS VM FIRST and wait for it to be fully online
Write-Host "  Restarting $DnsVmName..." -ForegroundColor Cyan
az vm restart `
    --resource-group $ResourceGroupName `
    --name $DnsVmName | Out-Null

# Wait for DNS VM to be fully running (provisioning state healthy)
Write-Host "  Waiting for $DnsVmName to fully recover..." -ForegroundColor Cyan
$maxAttempts = 60
$attempt = 0
$dnsVmReady = $false

while ($attempt -lt $maxAttempts) {
    $vmState = az vm get-instance-view `
        --resource-group $ResourceGroupName `
        --name $DnsVmName `
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" -o tsv
    
    if ($vmState -eq 'PowerState/running') {
        Write-Host "  ✓ $DnsVmName is running" -ForegroundColor Green
        $dnsVmReady = $true
        break
    }
    
    $attempt++
    Start-Sleep -Seconds 2
    Write-Host "  ⏳ Still waiting... ($attempt / $maxAttempts)" -ForegroundColor DarkGray
}

if (-not $dnsVmReady) {
    Write-Error "$DnsVmName failed to restart within timeout period"
}

# Wait additional time to ensure network is fully operational on DNS VM
Start-Sleep -Seconds 5

# Now restart the client VM (which will have a healthy DNS server available)
Write-Host "  Restarting $ClientVmName..." -ForegroundColor Cyan
az vm restart `
    --resource-group $ResourceGroupName `
    --name $ClientVmName | Out-Null

# Wait for client VM to be fully running
Write-Host "  Waiting for $ClientVmName to fully recover..." -ForegroundColor Cyan
$attempt = 0
$clientVmReady = $false

while ($attempt -lt $maxAttempts) {
    $vmState = az vm get-instance-view `
        --resource-group $ResourceGroupName `
        --name $ClientVmName `
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" -o tsv
    
    if ($vmState -eq 'PowerState/running') {
        Write-Host "  ✓ $ClientVmName is running" -ForegroundColor Green
        $clientVmReady = $true
        break
    }
    
    $attempt++
    Start-Sleep -Seconds 2
    Write-Host "  ⏳ Still waiting... ($attempt / $maxAttempts)" -ForegroundColor DarkGray
}

if (-not $clientVmReady) {
    Write-Error "$ClientVmName failed to restart within timeout period"
}

Write-Host '✓ Both VMs have rebooted and are online' -ForegroundColor Green

$elapsedTime = (Get-Date) - $script:deploymentStartTime
Write-Host ''
Write-Host 'Summary:' -ForegroundColor Cyan
Write-Host "  Zone: $ZoneName" -ForegroundColor White
Write-Host "  DNS VM: $DnsVmName ($dnsVmIp)" -ForegroundColor White
Write-Host "  Client VM: $ClientVmName ($clientVmIp)" -ForegroundColor White
Write-Host "  VNet DNS: $VnetName -> $dnsVmIp" -ForegroundColor White
Write-Host "  Deployment Time: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s" -ForegroundColor White

Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Run validation tests:' -ForegroundColor White
Write-Host '     ./scripts/phase1-2-test.ps1' -ForegroundColor Green
Write-Host '  2. Manual checks via Bastion:' -ForegroundColor White
Write-Host '     dig @127.0.0.1 dns.onprem.pvt +short' -ForegroundColor Green
Write-Host '     dig dns.onprem.pvt +short' -ForegroundColor Green
