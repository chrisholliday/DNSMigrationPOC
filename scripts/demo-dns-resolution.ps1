# DNS Resolution Demonstration Script
# 
# Purpose: Run comprehensive DNS resolution tests to demonstrate:
#   - Name resolution across all zones (onprem.pvt, azure.pvt, privatelink)
#   - Source of authority for each zone (BIND9 vs Azure Private DNS)
#   - Resolution chain for storage account private endpoints
#
# Usage:
#   ./scripts/demo-dns-resolution.ps1                    # Test from hub-vm-web
#   ./scripts/demo-dns-resolution.ps1 -VMName onprem-vm-web -ResourceGroup onprem-rg
#
# Use at different phases to show authority changes:
#   Phase 7:  All zones on BIND9
#   Phase 9:  privatelink.blob.core.windows.net migrated to Azure Private DNS
#   Phase 10: All zones migrated to Azure Private DNS

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = 'hub-rg',
    
    [Parameter(Mandatory = $false)]
    [string]$VMName = 'hub-vm-web'
)

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'DNS Resolution Demonstration' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host "Test VM: $VMName ($ResourceGroup)" -ForegroundColor Yellow
Write-Host ''

# Get storage accounts for testing
Write-Host 'Discovering storage accounts...' -ForegroundColor Cyan
$storage1 = (az storage account list -g spoke1-rg --query '[0].name' -o tsv 2>$null)
$storage2 = (az storage account list -g spoke2-rg --query '[0].name' -o tsv 2>$null)

if (-not $storage1 -or -not $storage2) {
    Write-Host '  ⚠ Storage accounts not found. Skipping storage tests.' -ForegroundColor Yellow
    $skipStorage = $true
}
else {
    Write-Host "  ✓ Spoke1 Storage: $storage1" -ForegroundColor Green
    Write-Host "  ✓ Spoke2 Storage: $storage2" -ForegroundColor Green
    $skipStorage = $false
}

Write-Host ''
Write-Host 'Running DNS tests...' -ForegroundColor Cyan
Write-Host ''

# Build the test script
$storageTests = if ($skipStorage) { '' } else {
    @"

echo ""
echo "=== Storage Account Resolution ==="
echo "Spoke1 Storage: $storage1"
dig +short $storage1.blob.core.windows.net
echo ""
echo "Spoke2 Storage: $storage2"
dig +short $storage2.blob.core.windows.net
"@ 
}

$storageChainTest = if ($skipStorage) { '' } else {
    @"

echo ""
echo "=== Storage Resolution Chain ==="
dig $storage1.blob.core.windows.net | grep -E "ANSWER SECTION" -A 5
"@ 
}

$demoScript = @"
#!/bin/bash

echo "════════════════════════════════════════════════════════════"
echo "DNS Configuration"
echo "════════════════════════════════════════════════════════════"
cat /etc/resolv.conf | grep nameserver

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Zone Resolution Tests"
echo "════════════════════════════════════════════════════════════"

echo ""
echo "=== On-Prem Zone (onprem.pvt) ==="
dig +short web.onprem.pvt
dig +short dns.onprem.pvt
dig +short client.onprem.pvt

echo ""
echo "=== Azure Zone (azure.pvt) ==="
dig +short web.azure.pvt
dig +short dns.azure.pvt
dig +short client.azure.pvt
$storageTests

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Authority Verification"
echo "════════════════════════════════════════════════════════════"

echo ""
echo "=== On-Prem Zone Authority (expect AA flag) ==="
dig @10.0.10.4 web.onprem.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "=== Azure Zone Authority (expect AA flag) ==="
dig @10.1.10.4 web.azure.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Forwarding Verification"
echo "════════════════════════════════════════════════════════════"

echo ""
echo "=== On-Prem DNS Querying Azure Zone (expect no AA flag) ==="
dig @10.0.10.4 web.azure.pvt | grep -E "flags:|ANSWER" -A 2

echo ""
echo "=== Hub DNS Querying On-Prem Zone (expect no AA flag) ==="
dig @10.1.10.4 web.onprem.pvt | grep -E "flags:|ANSWER" -A 2
$storageChainTest

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Tests Complete"
echo "════════════════════════════════════════════════════════════"
"@

# Execute the script on the VM
$output = az vm run-command invoke `
    --resource-group $ResourceGroup `
    --name $VMName `
    --command-id RunShellScript `
    --scripts $demoScript `
    --query 'value[0].message' -o tsv

# Parse and display the output with better formatting
$lines = $output -split "`n"
foreach ($line in $lines) {
    if ($line -match '^={60}') {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($line -match '^===') {
        Write-Host $line -ForegroundColor Yellow
    }
    elseif ($line -match 'flags:.*aa.*') {
        Write-Host $line -ForegroundColor Green  # Authoritative answer
    }
    elseif ($line -match 'flags:') {
        Write-Host $line -ForegroundColor Gray   # Non-authoritative
    }
    elseif ($line -match '^\d+\.\d+\.\d+\.\d+$') {
        Write-Host $line -ForegroundColor Green  # IP addresses
    }
    elseif ($line -match 'ANSWER SECTION') {
        Write-Host $line -ForegroundColor Cyan
    }
    else {
        Write-Host $line
    }
}

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Demonstration Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host 'Key Observations:' -ForegroundColor Cyan
Write-Host '  • Check for "aa" flag in dig output = authoritative answer' -ForegroundColor White
Write-Host '  • No "aa" flag = forwarded query' -ForegroundColor White
Write-Host '  • Storage accounts should show CNAME → privatelink chain' -ForegroundColor White
Write-Host '  • All IPs should be private (10.x.x.x)' -ForegroundColor White
Write-Host ''

exit 0
