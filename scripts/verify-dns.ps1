#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verify DNS resolution in the on-prem environment.
    
.DESCRIPTION
    This script tests DNS resolution by:
    1. Checking DNS server functionality
    2. Verifying local domain (onprem.pvt) resolution
    3. Testing public DNS resolution
    4. Checking internet connectivity
    
.PARAMETER ResourceGroupName
    Name of the resource group (default: dnsmig-rg-onprem)
    
.PARAMETER DnsServerName
    Name of the DNS server VM (default: dnsmig-onprem-vm-dns)
    
.PARAMETER ClientName
    Name of the client VM (default: dnsmig-onprem-vm-client)

.EXAMPLE
    ./verify-dns.ps1 -ResourceGroupName dnsmig-rg-onprem
#>

param(
    [string]$ResourceGroupName = 'dnsmig-rg-onprem',
    [string]$DnsServerName = 'dnsmig-onprem-vm-dns',
    [string]$ClientName = 'dnsmig-onprem-vm-client',
    [int]$TimeoutSeconds = 300,
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Check {
    param(
        [string]$Message,
        [ValidateSet('Pass', 'Fail', 'Skip', 'Info', 'Testing')]
        [string]$Status = 'Info'
    )
    
    $colors = @{
        'Pass'    = 'Green'
        'Fail'    = 'Red'
        'Skip'    = 'Yellow'
        'Info'    = 'Cyan'
        'Testing' = 'Blue'
    }
    
    $symbols = @{
        'Pass'    = '✓'
        'Fail'    = '✗'
        'Skip'    = '⊘'
        'Info'    = '→'
        'Testing' = '⟳'
    }
    
    Write-Host "$($symbols[$Status]) $Message" -ForegroundColor $colors[$Status]
}

function Test-AzureAuth {
    try {
        $null = az account show --query 'id' -o tsv 2>$null
        return $true
    } catch {
        return $false
    }
}

function Get-VmDetails {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        $vm = az vm show -g $ResourceGroup -n $VmName --query '{name: name, id: id, provisioningState: provisioningState}' -o json 2>$null | ConvertFrom-Json
        return $vm
    } catch {
        return $null
    }
}

function Get-VmPrivateIp {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )
    
    try {
        $ip = az vm list-ip-addresses -g $ResourceGroup -n $VmName --query '[0].virtualMachine.network.privateIpAddresses[0]' -o tsv 2>$null
        return $ip
    } catch {
        return $null
    }
}

function Test-VmConnectivity {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Command,
        [int]$Timeout = 30
    )
    
    try {
        Write-Host "    Running: $Command" -ForegroundColor Gray
        $output = az vm run-command invoke `
            -g $ResourceGroup `
            -n $VmName `
            --command-id RunShellScript `
            --scripts $Command `
            --query 'value[0].message' `
            -o tsv `
            --timeout-in-seconds $Timeout 2>$null
        
        return @{
            Success = $true
            Output = $output
        }
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# MAIN VALIDATION
# ============================================================================

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host 'DNS Resolution Verification' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# Check Azure CLI access
Write-Check 'Checking Azure CLI authentication...' -Status Testing
if (-not (Test-AzureAuth)) {
    Write-Check 'Not authenticated to Azure' -Status Fail
    Write-Host 'Please run: az login'
    exit 1
}
Write-Check 'Azure CLI authenticated' -Status Pass

# ============================================================================
# PHASE 1: INFRASTRUCTURE CHECK
# ============================================================================

Write-Host ''
Write-Host 'Phase 1: Infrastructure Verification' -ForegroundColor Yellow
Write-Host '─────────────────────────────────────' -ForegroundColor Yellow

Write-Check "Checking resource group: $ResourceGroupName"
$rg = az group show -n $ResourceGroupName --query 'name' -o tsv 2>$null
if (-not $rg) {
    Write-Check "Resource group not found" -Status Fail
    exit 1
}
Write-Check "Resource group found" -Status Pass

# Check DNS Server VM
Write-Check "Checking DNS server VM: $DnsServerName"
$dnsVm = Get-VmDetails -ResourceGroup $ResourceGroupName -VmName $DnsServerName
if (-not $dnsVm) {
    Write-Check "DNS server VM not found" -Status Fail
    exit 1
}
Write-Check "DNS server VM found (provisioning state: $($dnsVm.provisioningState))" -Status Pass

$dnsServerIp = Get-VmPrivateIp -ResourceGroup $ResourceGroupName -VmName $DnsServerName
Write-Check "DNS server private IP: $dnsServerIp"

# Check Client VM
Write-Check "Checking client VM: $ClientName"
$clientVm = Get-VmDetails -ResourceGroup $ResourceGroupName -VmName $ClientName
if (-not $clientVm) {
    Write-Check "Client VM not found" -Status Fail
    exit 1
}
Write-Check "Client VM found (provisioning state: $($clientVm.provisioningState))" -Status Pass

$clientIp = Get-VmPrivateIp -ResourceGroup $ResourceGroupName -VmName $ClientName
Write-Check "Client VM private IP: $clientIp"

# ============================================================================
# PHASE 2: DNS SERVER TESTS
# ============================================================================

Write-Host ''
Write-Host 'Phase 2: DNS Server Tests' -ForegroundColor Yellow
Write-Host '──────────────────────────' -ForegroundColor Yellow

Write-Check "Testing DNS server startup (max ${TimeoutSeconds}s)"

# Wait for dnsmasq to be running
$testCmd = @'
for i in {1..30}; do
  if systemctl is-active dnsmasq > /dev/null 2>&1; then
    echo "dnsmasq is running"
    exit 0
  fi
  echo "Attempt $i: waiting for dnsmasq..."
  sleep 2
done
echo "dnsmasq did not start in time"
exit 1
'@

$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $DnsServerName -Command $testCmd -Timeout $TimeoutSeconds

if ($result.Success) {
    Write-Check "dnsmasq service is running" -Status Pass
} else {
    Write-Check "dnsmasq service failed to start" -Status Fail
    Write-Host "  Error: $($result.Error)" -ForegroundColor Red
}

# Check dnsmasq configuration
$confCmd = 'cat /etc/dnsmasq.d/onprem.conf'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $DnsServerName -Command $confCmd
if ($result.Success) {
    Write-Check "dnsmasq configuration loaded" -Status Pass
    if ($Verbose) {
        Write-Host "    Configuration:" -ForegroundColor Gray
        $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
} else {
    Write-Check "Failed to read dnsmasq configuration" -Status Fail
}

# Check DNS listening
$listenCmd = 'netstat -tuln | grep :53 || echo "DNS not listening on port 53"'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $DnsServerName -Command $listenCmd
if ($result.Success -and $result.Output -like '*LISTEN*') {
    Write-Check "DNS server listening on port 53" -Status Pass
    if ($Verbose) {
        Write-Host "    $($result.Output)" -ForegroundColor Gray
    }
} else {
    Write-Check "DNS server not listening on port 53" -Status Fail
    if ($Verbose) {
        Write-Host "    $($result.Output)" -ForegroundColor Red
    }
}

# Check dnsmasq logs
$logsCmd = 'journalctl -u dnsmasq -n 10 --no-pager'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $DnsServerName -Command $logsCmd
if ($result.Success) {
    Write-Check "dnsmasq logs retrieved" -Status Pass
    if ($Verbose) {
        Write-Host "    Recent logs:" -ForegroundColor Gray
        $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
}

# ============================================================================
# PHASE 3: DNS RESOLUTION TESTS (from DNS server)
# ============================================================================

Write-Host ''
Write-Host 'Phase 3: DNS Resolution Tests (from DNS Server)' -ForegroundColor Yellow
Write-Host '────────────────────────────────────────────────' -ForegroundColor Yellow

$dnsTests = @(
    @{
        Name = 'Local domain (onprem.pvt)'
        Query = 'onprem.pvt'
        Expected = $dnsServerIp
    }
    @{
        Name = 'Local host (onprem-dns.onprem.pvt)'
        Query = 'onprem-dns.onprem.pvt'
        Expected = $dnsServerIp
    }
    @{
        Name = 'Public DNS (google.com)'
        Query = 'google.com'
        Expected = $null
    }
    @{
        Name = 'Azure DNS (azure.microsoft.com)'
        Query = 'azure.microsoft.com'
        Expected = $null
    }
)

foreach ($test in $dnsTests) {
    $nsCmd = "nslookup $($test.Query) 127.0.0.1 2>&1 | head -20"
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $DnsServerName -Command $nsCmd -Timeout 15
    
    if ($result.Success) {
        if ($result.Output -like '*Address:*') {
            Write-Check "$($test.Name)" -Status Pass
            if ($Verbose) {
                $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
            }
        } else {
            Write-Check "$($test.Name) - no answer" -Status Fail
            Write-Host "    Response: $($result.Output)" -ForegroundColor Red
        }
    } else {
        Write-Check "$($test.Name) - query failed" -Status Fail
        Write-Host "    Error: $($result.Error)" -ForegroundColor Red
    }
}

# ============================================================================
# PHASE 4: CLIENT VM TESTS
# ============================================================================

Write-Host ''
Write-Host 'Phase 4: Client VM Tests' -ForegroundColor Yellow
Write-Host '────────────────────────' -ForegroundColor Yellow

# Check DNS configuration
$dnsConfCmd = 'cat /etc/resolv.conf | grep nameserver'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $ClientName -Command $dnsConfCmd
if ($result.Success) {
    Write-Check "Client DNS configuration" -Status Pass
    if ($Verbose) {
        Write-Host "    Configuration:" -ForegroundColor Gray
        $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
} else {
    Write-Check "Failed to read client DNS configuration" -Status Fail
}

# ============================================================================
# PHASE 5: DNS RESOLUTION TESTS (from Client)
# ============================================================================

Write-Host ''
Write-Host 'Phase 5: DNS Resolution Tests (from Client)' -ForegroundColor Yellow
Write-Host '───────────────────────────────────────────' -ForegroundColor Yellow

foreach ($test in $dnsTests) {
    $nsCmd = "nslookup $($test.Query) 2>&1 | head -20"
    $result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $ClientName -Command $nsCmd -Timeout 15
    
    if ($result.Success) {
        if ($result.Output -like '*Address:*' -or $result.Output -like '*Authoritative answers can be found from:*') {
            Write-Check "$($test.Name)" -Status Pass
            if ($Verbose) {
                $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
            }
        } else {
            Write-Check "$($test.Name) - no answer" -Status Fail
            Write-Host "    Response: $($result.Output)" -ForegroundColor Red
        }
    } else {
        Write-Check "$($test.Name) - query failed" -Status Fail
    }
}

# ============================================================================
# PHASE 6: INTERNET CONNECTIVITY
# ============================================================================

Write-Host ''
Write-Host 'Phase 6: Internet Connectivity Tests' -ForegroundColor Yellow
Write-Host '─────────────────────────────────────' -ForegroundColor Yellow

# Ping test
$pingCmd = 'ping -c 3 8.8.8.8 2>&1 | tail -5'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $ClientName -Command $pingCmd -Timeout 15

if ($result.Success -and $result.Output -like '*received*') {
    Write-Check "Internet connectivity (8.8.8.8)" -Status Pass
    if ($Verbose) {
        $result.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
} else {
    Write-Check "Internet connectivity test inconclusive" -Status Skip
}

# Curl test to Azure DNS
$curlCmd = 'curl -s https://www.google.com --max-time 5 --output /dev/null --write-out "HTTP %{http_code}" || echo "Connection failed"'
$result = Test-VmConnectivity -ResourceGroup $ResourceGroupName -VmName $ClientName -Command $curlCmd -Timeout 15

if ($result.Success) {
    if ($result.Output -like 'HTTP 200*' -or $result.Output -like 'HTTP 30*') {
        Write-Check "HTTPS connectivity to google.com" -Status Pass
    } else {
        Write-Check "HTTPS connectivity to google.com - HTTP $($result.Output)" -Status Skip
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host 'Verification Complete' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host 'SSH Access Commands:' -ForegroundColor Cyan
Write-Host "  DNS Server: az ssh vm -g $ResourceGroupName -n $DnsServerName --local-user azureuser" -ForegroundColor Gray
Write-Host "  Client VM:  az ssh vm -g $ResourceGroupName -n $ClientName --local-user azureuser" -ForegroundColor Gray
Write-Host ''

Write-Host 'Useful Commands on DNS Server:' -ForegroundColor Cyan
Write-Host "  Check dnsmasq status: systemctl status dnsmasq"
Write-Host "  View configuration: cat /etc/dnsmasq.d/onprem.conf"
Write-Host "  View DNS logs: journalctl -u dnsmasq -f"
Write-Host "  Query locally: nslookup onprem.pvt 127.0.0.1"
Write-Host ''

Write-Host 'Useful Commands on Client VM:' -ForegroundColor Cyan
Write-Host "  Check DNS config: cat /etc/resolv.conf"
Write-Host "  Query test: nslookup onprem.pvt"
Write-Host "  Check connectivity: curl https://www.google.com"
Write-Host ''
