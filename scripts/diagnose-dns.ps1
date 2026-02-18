#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Diagnose DNS server configuration issues.
    
.DESCRIPTION
    Runs comprehensive diagnostic checks on the DNS server to identify
    why dnsmasq isn't working properly.
    
.PARAMETER ResourceGroupName
    Name of the resource group (default: dnsmig-rg-onprem)
    
.PARAMETER DnsServerName
    Name of the DNS server VM (default: dnsmig-onprem-vm-dns)

.EXAMPLE
    ./diagnose-dns.ps1 -ResourceGroupName dnsmig-rg-onprem
#>

param(
    [string]$ResourceGroupName = 'dnsmig-rg-onprem',
    [string]$DnsServerName = 'dnsmig-onprem-vm-dns'
)

$ErrorActionPreference = 'Continue'

function Run-Command {
    param(
        [string]$Description,
        [string]$Command
    )
    
    Write-Host ''
    Write-Host "► $Description" -ForegroundColor Cyan
    Write-Host "  Command: $Command" -ForegroundColor DarkGray
    Write-Host '  Output:' -ForegroundColor DarkGray
    
    try {
        $result = az vm run-command invoke `
            -g $ResourceGroupName `
            -n $DnsServerName `
            --command-id RunShellScript `
            --scripts $Command `
            --query 'value[0].message' `
            -o tsv `
            --timeout-in-seconds 15 2>$null
        
        if ($result) {
            $result | ForEach-Object { Write-Host "    $_" }
        }
        else {
            Write-Host '    (no output)' -ForegroundColor Gray
        }
        return $result
    }
    catch {
        Write-Host "    ERROR: $_" -ForegroundColor Red
        return $null
    }
}

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'DNS Server Diagnostic Report' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host "Server: $DnsServerName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ''

# ============================================================================
# CHECK 1: Package Installation
# ============================================================================

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '1. PACKAGE INSTALLATION CHECK' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'Check if dnsmasq is installed' `
    "which dnsmasq && dnsmasq --version | head -3 || echo 'NOT INSTALLED'"

Run-Command 'Check if bind-utils is installed' `
    "which nslookup && echo 'nslookup found' || echo 'NOT INSTALLED'"

Run-Command 'Check if curl is installed' `
    "which curl && curl --version | head -2 || echo 'NOT INSTALLED'"

# ============================================================================
# CHECK 2: Service Status
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '2. SERVICE STATUS CHECK' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'systemctl status for dnsmasq' `
    "systemctl status dnsmasq || echo 'Service not running'"

Run-Command 'dnsmasq process check' `
    "ps aux | grep dnsmasq | grep -v grep || echo 'Process not found'"

# ============================================================================
# CHECK 3: Configuration
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '3. CONFIGURATION CHECK' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'Contents of /etc/dnsmasq.d/onprem.conf' `
    "cat /etc/dnsmasq.d/onprem.conf 2>/dev/null || echo 'File not found'"

Run-Command 'Contents of /etc/dnsmasq.hosts' `
    "cat /etc/dnsmasq.hosts 2>/dev/null || echo 'File not found'"

Run-Command 'DNS listen addresses' `
    "netstat -tulnp | grep -E ':(53|5353)' || echo 'DNS port 53 not listening'"

# ============================================================================
# CHECK 4: Logs
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '4. LOG FILES CHECK' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'Recent dnsmasq systemd logs' `
    "journalctl -u dnsmasq -n 20 --no-pager || echo 'No systemd logs'"

Run-Command 'Cloud-init output log (last 50 lines)' `
    "tail -50 /var/log/cloud-init-output.log || echo 'Cloud-init log not found'"

Run-Command 'Cloud-init main log (last 30 lines)' `
    "tail -30 /var/log/cloud-init.log || echo 'Cloud-init log not found'"

# ============================================================================
# CHECK 5: Network and DNS Tests
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '5. NETWORK AND DNS TESTS' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'System DNS configuration (/etc/resolv.conf)' `
    "cat /etc/resolv.conf || echo 'File not found'"

Run-Command 'Test local loopback DNS query' `
    "nslookup localhost 127.0.0.1 || echo 'Query failed'"

Run-Command 'Test dnsmasq with dig' `
    "dig @127.0.0.1 onprem.pvt +short || echo 'Dig failed'"

Run-Command 'Test internet connectivity (ping 8.8.8.8)' `
    "ping -c 2 8.8.8.8 && echo 'Internet OK' || echo 'No internet'"

# ============================================================================
# CHECK 6: Cloud-Init Status
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow
Write-Host '6. CLOUD-INIT STATUS CHECK' -ForegroundColor Yellow
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Yellow

Run-Command 'Cloud-init status' `
    "cloud-init status 2>/dev/null || echo 'Cloud-init status command failed'"

Run-Command 'List cloud-init boot-finished marker' `
    "ls -la /var/lib/cloud/instance/boot-finished 2>/dev/null || echo 'Marker not found'"

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'DIAGNOSTIC COMPLETE' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Yellow
Write-Host '1. Review the output above for errors or missing packages'
Write-Host '2. If dnsmasq is not installed:' -ForegroundColor Yellow
Write-Host '   • SSH to the VM and manually install packages:' -ForegroundColor Gray
Write-Host '   • sudo apt-get update' -ForegroundColor DarkGray
Write-Host '   • sudo apt-get install -y dnsmasq bind-utils curl' -ForegroundColor DarkGray
Write-Host '   • sudo systemctl restart dnsmasq' -ForegroundColor DarkGray
Write-Host ''
Write-Host "3. If dnsmasq won't start:" -ForegroundColor Yellow
Write-Host '   • Check /var/log/dnsmasq.log for configuration errors:' -ForegroundColor Gray
Write-Host '   • sudo systemctl stop dnsmasq' -ForegroundColor DarkGray
Write-Host '   • sudo dnsmasq -d (run in debug mode to see errors)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '4. SSH to DNS server for interactive debugging:' -ForegroundColor Yellow
Write-Host "   az ssh vm -g $ResourceGroupName -n $DnsServerName --local-user azureuser" -ForegroundColor Gray
Write-Host ''
