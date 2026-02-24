#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fix Phase 7 on-prem DNS to forward blob queries to hub.

.DESCRIPTION
This script configures the on-prem DNS server to forward blob.core.windows.net
and privatelink.blob.core.windows.net queries to the hub DNS server.

This is a manual fix for the missing on-prem blob forwarding configuration.
#>

param(
    [string]$OnpremResourceGroupName = 'rg-onprem-dnsmig'
)

$ErrorActionPreference = 'Stop'

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Phase 7 Fix: Configure On-Prem Blob Forwarding' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host 'This will configure on-prem DNS to forward blob queries to hub DNS (10.1.10.4)' -ForegroundColor Yellow
Write-Host ''

$updateOnpremScript = @'
#!/bin/bash
set -e

echo "Configuring blob.core.windows.net forwarding..."

# Configure conditional forwarding for blob.core.windows.net
if ! grep -q 'zone "blob.core.windows.net"' /etc/bind/named.conf.local; then
    cat >> /etc/bind/named.conf.local << 'EOFZONE'

// Forward blob queries to hub DNS (covers private endpoints)
zone "blob.core.windows.net" {
    type forward;
    forward only;
    forwarders { 10.1.10.4; };
};
EOFZONE
    echo "  ✓ Added blob.core.windows.net forwarding"
else
    echo "  ✓ blob.core.windows.net forwarding already configured"
fi

# Configure conditional forwarding for privatelink.blob.core.windows.net
if ! grep -q 'zone "privatelink.blob.core.windows.net"' /etc/bind/named.conf.local; then
    cat >> /etc/bind/named.conf.local << 'EOFZONE'

// Forward privatelink blob queries to hub DNS
zone "privatelink.blob.core.windows.net" {
    type forward;
    forward only;
    forwarders { 10.1.10.4; };
};
EOFZONE
    echo "  ✓ Added privatelink.blob.core.windows.net forwarding"
else
    echo "  ✓ privatelink.blob.core.windows.net forwarding already configured"
fi

# Validate and reload
echo ""
echo "Validating BIND9 configuration..."
sudo named-checkconf

echo "Reloading BIND9..."
sudo systemctl reload bind9

echo ""
echo "✓ On-prem DNS configured to forward blob queries to hub"
'@

Write-Host 'Updating on-prem DNS configuration...' -ForegroundColor Cyan

$output = az vm run-command invoke `
    --resource-group $OnpremResourceGroupName `
    --name 'onprem-vm-dns' `
    --command-id RunShellScript `
    --scripts $updateOnpremScript `
    --query 'value[0].message' -o tsv

Write-Host $output

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Fix Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. Run: ./scripts/phase7-test.ps1' -ForegroundColor White
Write-Host '  2. All tests should now pass (5/5)' -ForegroundColor White
Write-Host ''

exit 0
