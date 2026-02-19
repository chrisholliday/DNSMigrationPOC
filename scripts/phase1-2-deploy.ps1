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
Write-Host '[2/5] Configuring BIND on DNS VM...' -ForegroundColor Yellow

$serial = Get-Date -Format 'yyyyMMdd01'

$zoneFile = @"
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

$zoneFileB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($zoneFile))

$bindScript = @"
#!/bin/bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y bind9 bind9utils dnsutils

sudo tee /etc/bind/named.conf.options > /dev/null <<EOF
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { any; };
    listen-on { 127.0.0.1; $dnsVmIp; };
    listen-on-v6 { none; };
    forwarders { $ForwarderIp; };
    dnssec-validation no;
};
EOF

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
zone "$ZoneName" {
  type master;
  file "/etc/bind/db.$ZoneName";
};
EOF

echo '$zoneFileB64' | base64 -d | sudo tee /etc/bind/db.$ZoneName > /dev/null

sudo named-checkconf
sudo named-checkzone $ZoneName /etc/bind/db.$ZoneName
sudo systemctl enable bind9
sudo systemctl restart bind9
"@

$bindOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts $bindScript `
    --query 'value[0].message' -o tsv

if ($LASTEXITCODE -ne 0) {
    Write-Error "BIND configuration failed on $DnsVmName. Output: $bindOutput"
}

Write-Host '✓ DNS VM configured with BIND and zone file' -ForegroundColor Green

Write-Host ''
Write-Host '[3/5] Validating DNS VM local resolution...' -ForegroundColor Yellow

$validationOutput = az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name $DnsVmName `
    --command-id RunShellScript `
    --scripts "dig @127.0.0.1 +short dns.$ZoneName" `
    --query 'value[0].message' -o tsv

if ($validationOutput -notmatch '\b\d{1,3}(\.\d{1,3}){3}\b') {
    Write-Error "DNS validation failed on $DnsVmName. Output: $validationOutput"
}

Write-Host '✓ DNS VM responds for local zone queries' -ForegroundColor Green

Write-Host ''
Write-Host '[4/5] Updating VNet DNS servers...' -ForegroundColor Yellow

az network vnet update `
    --resource-group $ResourceGroupName `
    --name $VnetName `
    --dns-servers $dnsVmIp | Out-Null

Write-Host "✓ VNet DNS set to $dnsVmIp" -ForegroundColor Green

Write-Host ''
Write-Host '[5/5] Rebooting VMs to apply DNS settings...' -ForegroundColor Yellow

az vm restart `
    --resource-group $ResourceGroupName `
    --name $DnsVmName | Out-Null

az vm restart `
    --resource-group $ResourceGroupName `
    --name $ClientVmName | Out-Null

Write-Host '✓ VMs restarted' -ForegroundColor Green

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
