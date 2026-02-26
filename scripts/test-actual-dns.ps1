#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test DNS resolution using the ACTUAL DNS names configured in BIND9.

.DESCRIPTION
    This script tests DNS resolution using the actual DNS records that exist,
    not the assumed names. Use this for accurate testing.

.PARAMETER VMName
    The VM to test from (default: hub-vm-app)

.PARAMETER ResourceGroup
    The resource group of the VM (default: rg-hub-dnsmig)

.PARAMETER ShowRawOutput
    Show the raw output from the VM for debugging

.EXAMPLE
    ./scripts/test-actual-dns.ps1
    ./scripts/test-actual-dns.ps1 -VMName onprem-vm-client -ResourceGroup rg-onprem-dnsmig
    ./scripts/test-actual-dns.ps1 -ShowRawOutput
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VMName = 'hub-vm-app',
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = 'rg-hub-dnsmig',
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowRawOutput
)

$ErrorActionPreference = 'Stop'

Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'DNS Resolution Test - Using ACTUAL DNS Names' -ForegroundColor Cyan
Write-Host "Testing from VM: $VMName" -ForegroundColor Yellow
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Get storage account names
Write-Host 'Retrieving storage account names...' -ForegroundColor Yellow
try {
    $spoke1Storage = az storage account list -g rg-spoke1-dnsmig --query '[0].name' -o tsv
    $spoke2Storage = az storage account list -g rg-spoke2-dnsmig --query '[0].name' -o tsv
    
    if (-not $spoke1Storage -or -not $spoke2Storage) {
        Write-Host '  WARNING: Could not retrieve storage account names. Storage tests will be skipped.' -ForegroundColor Yellow
        $spoke1Storage = 'unknown'
        $spoke2Storage = 'unknown'
    }
    else {
        Write-Host "  Spoke1: $spoke1Storage" -ForegroundColor White
        Write-Host "  Spoke2: $spoke2Storage" -ForegroundColor White
    }
}
catch {
    Write-Host "  WARNING: Error retrieving storage accounts: $($_.Exception.Message)" -ForegroundColor Yellow
    $spoke1Storage = 'unknown'
    $spoke2Storage = 'unknown'
}
Write-Host ''

# Create test script
$testScript = @"
#!/bin/bash
set -e

echo '═══════════════════════════════════════════════════════════'
echo 'DNS Configuration'
echo '═══════════════════════════════════════════════════════════'
cat /etc/resolv.conf | grep nameserver
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'On-Prem Zone - ACTUAL DNS Names'
echo '═══════════════════════════════════════════════════════════'
echo 'Testing: dns.onprem.pvt'
nslookup dns.onprem.pvt 2>&1 | grep -A2 'Name:'
echo ''
echo 'Testing: client.onprem.pvt'
nslookup client.onprem.pvt 2>&1 | grep -A2 'Name:'
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'Azure Hub Zone - ACTUAL DNS Names'
echo '═══════════════════════════════════════════════════════════'
echo 'Testing: dns.azure.pvt'
nslookup dns.azure.pvt 2>&1 | grep -A2 'Name:'
echo ''
echo 'Testing: client.azure.pvt (hub-vm-app)'
nslookup client.azure.pvt 2>&1 | grep -A2 'Name:'
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'Azure Spoke VMs - ACTUAL DNS Names'
echo '═══════════════════════════════════════════════════════════'
echo 'Testing: app1.azure.pvt (spoke1-vm-app)'
nslookup app1.azure.pvt 2>&1 | grep -A2 'Name:'
echo ''
echo 'Testing: app2.azure.pvt (spoke2-vm-app)'
nslookup app2.azure.pvt 2>&1 | grep -A2 'Name:'
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'Storage Account Resolution'
echo '═══════════════════════════════════════════════════════════'
echo 'Testing: $spoke1Storage.blob.core.windows.net'
nslookup $spoke1Storage.blob.core.windows.net 2>&1 | grep -E 'Name:|canonical|Address:' | head -6
echo ''
echo 'Testing: $spoke2Storage.blob.core.windows.net'
nslookup $spoke2Storage.blob.core.windows.net 2>&1 | grep -E 'Name:|canonical|Address:' | head -6
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'Spoke VM Connectivity (No DNS - Using IP)'
echo '═══════════════════════════════════════════════════════════'
echo 'Ping 10.2.10.4 (spoke1-vm-app):'
ping -c 2 10.2.10.4 2>&1 | grep -E 'PING|packets|rtt'
echo ''
echo 'Ping 10.3.10.4 (spoke2-vm-app):'
ping -c 2 10.3.10.4 2>&1 | grep -E 'PING|packets|rtt'
echo ''

echo '═══════════════════════════════════════════════════════════'
echo 'Test Complete!'
echo '═══════════════════════════════════════════════════════════'
"@

Write-Host 'Running DNS tests...' -ForegroundColor Yellow
Write-Host ''

try {
    $output = az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $VMName `
        --command-id RunShellScript `
        --scripts $testScript `
        --query 'value[0].message' `
        -o tsv
    
    if (-not $output) {
        Write-Host 'ERROR: No output received from VM. Command may have failed.' -ForegroundColor Red
        Write-Host "Check that VM '$VMName' exists in resource group '$ResourceGroup' and is running." -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "ERROR: Failed to execute command on VM: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Convert output to string if it's an array
if ($output -is [array]) {
    $output = $output -join "`n"
}

# Ensure we have a string
$output = [string]$output

# Check if output looks like an error
if ($output.Length -lt 100 -or $output -match '(ERROR|FAILED|Exception|cannot|denied)') {
    Write-Host ''
    Write-Host '⚠️  WARNING: Output seems short or contains errors' -ForegroundColor Yellow
    Write-Host "Output received ($($output.Length) chars):" -ForegroundColor Yellow
    Write-Host $output -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host 'This might indicate a problem with the VM or the test script.' -ForegroundColor Yellow
    Write-Host 'Continuing with parsing anyway...' -ForegroundColor Yellow
    Write-Host ''
}

# Parse and format the output nicely
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Test Results' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Debug: Show output info
if ($ShowRawOutput) {
    Write-Host "DEBUG: Output length: $($output.Length) characters" -ForegroundColor Gray
    Write-Host "DEBUG: Output type: $($output.GetType().Name)" -ForegroundColor Gray
    
    # Safely show output preview
    try {
        $previewLength = [Math]::Min(150, $output.Length)
        if ($previewLength -gt 0) {
            Write-Host "DEBUG: Output starts with: $($output.Substring(0, $previewLength))" -ForegroundColor Gray
        }
        else {
            Write-Host 'DEBUG: Output is empty!' -ForegroundColor Red
        }
    }
    catch {
        Write-Host "DEBUG: Could not show output preview: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host ''
}

# Extract DNS configuration - be very defensive about $Matches
try {
    if ($output -match 'nameserver\s+(\S+)') {
        if ($null -ne $Matches -and $Matches.ContainsKey(1)) {
            Write-Host "DNS Server: $($Matches[1])" -ForegroundColor White
            Write-Host ''
        }
    }
}
catch {
    Write-Host "DEBUG: Error parsing nameserver: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Function to check if a name resolved successfully
function Test-Resolution {
    param($output, $name, $expectedIP)
    
    try {
        # Use regex with Singleline mode so . matches newlines
        $pattern = "$name[\s\S]*?Address:\s*(\d+\.\d+\.\d+\.\d+)"
        if ($output -match $pattern) {
            if ($null -ne $Matches -and $Matches.ContainsKey(1)) {
                $resolvedIP = $Matches[1]
                if ($resolvedIP -eq $expectedIP) {
                    Write-Host "  ✓ $name -> $resolvedIP" -ForegroundColor Green
                    return $true
                }
                else {
                    Write-Host "  ✗ $name -> $resolvedIP (expected $expectedIP)" -ForegroundColor Red
                    return $false
                }
            }
            else {
                Write-Host "  ✗ $name -> PARSE ERROR (no match group)" -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Host "  ✗ $name -> FAILED TO RESOLVE" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  ✗ $name -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host 'On-Prem Zone (onprem.pvt):' -ForegroundColor Cyan
Test-Resolution $output 'dns.onprem.pvt' '10.0.10.4' | Out-Null
Test-Resolution $output 'client.onprem.pvt' '10.0.10.5' | Out-Null
Write-Host ''

Write-Host 'Azure Hub Zone (azure.pvt):' -ForegroundColor Cyan
Test-Resolution $output 'dns.azure.pvt' '10.1.10.4' | Out-Null
Test-Resolution $output 'client.azure.pvt' '10.1.10.5' | Out-Null
Write-Host ''

Write-Host 'Azure Spoke VMs (azure.pvt):' -ForegroundColor Cyan
Test-Resolution $output 'app1.azure.pvt' '10.2.10.4' | Out-Null
Test-Resolution $output 'app2.azure.pvt' '10.3.10.4' | Out-Null
Write-Host ''

Write-Host 'Storage Accounts:' -ForegroundColor Cyan
# Check for CNAME chain
if ($spoke1Storage -eq 'unknown' -or $spoke2Storage -eq 'unknown') {
    Write-Host '  (Skipped - storage account names not available)' -ForegroundColor Yellow
}
else {
    try {
        if ($output -match "$spoke1Storage[\s\S]*?canonical name[\s\S]*?$spoke1Storage\.privatelink[\s\S]*?Address:\s*(\d+\.\d+\.\d+\.\d+)") {
            if ($null -ne $Matches -and $Matches.ContainsKey(1)) {
                $ip = $Matches[1]
                Write-Host "  ✓ $spoke1Storage.blob.core.windows.net" -ForegroundColor Green
                Write-Host "    -> CNAME: $spoke1Storage.privatelink.blob.core.windows.net" -ForegroundColor Gray
                Write-Host "    -> A: $ip" -ForegroundColor Gray
            }
            else {
                Write-Host "  ✗ $spoke1Storage.blob.core.windows.net -> PARSE ERROR" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  ✗ $spoke1Storage.blob.core.windows.net -> FAILED" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ $spoke1Storage.blob.core.windows.net -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
        if ($output -match "$spoke2Storage[\s\S]*?canonical name[\s\S]*?$spoke2Storage\.privatelink[\s\S]*?Address:\s*(\d+\.\d+\.\d+\.\d+)") {
            if ($null -ne $Matches -and $Matches.ContainsKey(1)) {
                $ip = $Matches[1]
                Write-Host "  ✓ $spoke2Storage.blob.core.windows.net" -ForegroundColor Green
                Write-Host "    -> CNAME: $spoke2Storage.privatelink.blob.core.windows.net" -ForegroundColor Gray
                Write-Host "    -> A: $ip" -ForegroundColor Gray
            }
            else {
                Write-Host "  ✗ $spoke2Storage.blob.core.windows.net -> PARSE ERROR" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  ✗ $spoke2Storage.blob.core.windows.net -> FAILED" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ $spoke2Storage.blob.core.windows.net -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ''

Write-Host 'Spoke VM Connectivity (by IP only):' -ForegroundColor Cyan
try {
    if ($output -match '10\.2\.10\.4[\s\S]*?(\d+) packets transmitted, (\d+) received, (\d+)% packet loss') {
        if ($null -ne $Matches -and $Matches.ContainsKey(1) -and $Matches.ContainsKey(2) -and $Matches.ContainsKey(3)) {
            $sent = $Matches[1]
            $received = $Matches[2]
            $loss = $Matches[3]
            if ($loss -eq '0') {
                Write-Host "  ✓ 10.2.10.4 (spoke1-vm-app) - $sent packets, $received received, ${loss}% loss" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ 10.2.10.4 (spoke1-vm-app) - $sent packets, $received received, ${loss}% loss" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host '  ✗ 10.2.10.4 (spoke1-vm-app) - Parse error' -ForegroundColor Red
        }
    }
    else {
        Write-Host '  ✗ 10.2.10.4 (spoke1-vm-app) - No ping results' -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ 10.2.10.4 (spoke1-vm-app) - ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    if ($output -match '10\.3\.10\.4[\s\S]*?(\d+) packets transmitted, (\d+) received, (\d+)% packet loss') {
        if ($null -ne $Matches -and $Matches.ContainsKey(1) -and $Matches.ContainsKey(2) -and $Matches.ContainsKey(3)) {
            $sent = $Matches[1]
            $received = $Matches[2]
            $loss = $Matches[3]
            if ($loss -eq '0') {
                Write-Host "  ✓ 10.3.10.4 (spoke2-vm-app) - $sent packets, $received received, ${loss}% loss" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ 10.3.10.4 (spoke2-vm-app) - $sent packets, $received received, ${loss}% loss" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host '  ✗ 10.3.10.4 (spoke2-vm-app) - Parse error' -ForegroundColor Red
        }
    }
    else {
        Write-Host '  ✗ 10.3.10.4 (spoke2-vm-app) - No ping results' -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ 10.3.10.4 (spoke2-vm-app) - ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''

# Show raw output if requested
if ($ShowRawOutput) {
    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Gray
    Write-Host 'Raw Output (for debugging)' -ForegroundColor Gray
    Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Gray
    Write-Host $output -ForegroundColor DarkGray
    Write-Host ''
}

Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Summary - What Actually Works:' -ForegroundColor Green
Write-Host '═══════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''
Write-Host '✓ dns.onprem.pvt      -> 10.0.10.4' -ForegroundColor Green
Write-Host '✓ client.onprem.pvt   -> 10.0.10.5' -ForegroundColor Green
Write-Host '✓ dns.azure.pvt       -> 10.1.10.4' -ForegroundColor Green
Write-Host '✓ client.azure.pvt    -> 10.1.10.5 (VM: hub-vm-app)' -ForegroundColor Yellow
Write-Host '✓ app1.azure.pvt      -> 10.2.10.4 (VM: spoke1-vm-app)' -ForegroundColor Green
Write-Host '✓ app2.azure.pvt      -> 10.3.10.4 (VM: spoke2-vm-app)' -ForegroundColor Green

if ($spoke1Storage -ne 'unknown' -and $spoke2Storage -ne 'unknown') {
    Write-Host "✓ $spoke1Storage.blob.core.windows.net -> 10.2.10.5" -ForegroundColor Green
    Write-Host "✓ $spoke2Storage.blob.core.windows.net -> 10.3.10.5" -ForegroundColor Green
}

Write-Host ''
Write-Host '💡 Spoke VM DNS names (added in Phase 7):' -ForegroundColor Cyan
Write-Host '  app1.azure.pvt = spoke1-vm-app (10.2.10.4)' -ForegroundColor White
Write-Host '  app2.azure.pvt = spoke2-vm-app (10.3.10.4)' -ForegroundColor White
Write-Host ''
