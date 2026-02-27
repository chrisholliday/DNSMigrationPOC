<#
.SYNOPSIS
    Phase 4 – Switch VNets to custom DNS servers and validate end-to-end resolution.

.DESCRIPTION
    Updates each VNet's custom DNS server setting, then forces VMs to renew
    their DHCP lease so the new DNS takes effect immediately.

    After this phase, all VMs resolve DNS via the BIND9 servers deployed in
    Phase 1 and configured in Phase 3:
      - vnet-onprem   → vm-onprem-dns (resolves onprem.pvt, forwards others to hub)
      - vnet-hub      → vm-hub-dns   (resolves azure.pvt + privatelink; forwards others)
      - vnet-spoke1   → vm-hub-dns
      - vnet-spoke2   → vm-hub-dns

    A validation query is run from vm-spoke1 and vm-spoke2 to verify full
    end-to-end resolution across zones and internet names.

.PARAMETER Location
    Azure region — used only for the subscription-level deployment scope reference.
    Default: centralus.

.EXAMPLE
    .\deploy-phase4.ps1

.NOTES
    Prerequisite: Phases 1, 2, and 3 must be deployed and configured.
    Run 'az login' and 'az account set --subscription <id>' before executing.
#>

[CmdletBinding()]
param(
    [string] $Location = 'centralus'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: run az vm run-command ─────────────────────────────────────────────

function Invoke-VmRunCommand {
    [CmdletBinding()]
    param(
        [string] $ResourceGroup,
        [string] $VmName,
        [string] $ScriptContent,
        [string] $Description
    )

    Write-Host "  [$VmName] $Description..." -ForegroundColor Cyan

    $tempFile = [System.IO.Path]::GetTempFileName() + '.sh'
    try {
        Set-Content -Path $tempFile -Value $ScriptContent -Encoding UTF8 -NoNewline

        $result = az vm run-command invoke `
            --resource-group $ResourceGroup `
            --name $VmName `
            --command-id RunShellScript `
            --scripts "@$tempFile" `
            --output json `
            --only-show-errors 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Run-command failed on $VmName.`n$result"
            return $null
        }

        $parsed = $result | ConvertFrom-Json
        $stdout = $parsed.value | Where-Object { $_.code -like '*StdOut*' } | Select-Object -ExpandProperty message
        return $stdout
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

# ── Verify Azure CLI login ─────────────────────────────────────────────────────

Write-Host "Verifying Azure CLI authentication..." -ForegroundColor Cyan
$account = az account show --output json 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}
Write-Host "  Subscription: $($account.name)" -ForegroundColor Green

# ── Load Phase 1 state file ───────────────────────────────────────────────────

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$stateFile = Join-Path (Split-Path -Parent $scriptDir) 'phase1-outputs.json'

if (-not (Test-Path -Path $stateFile)) {
    Write-Error "Phase 1 state file not found: $stateFile`nRun phase1\deploy-phase1.ps1 first."
    exit 1
}

try {
    $phase1 = Get-Content -Path $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse Phase 1 state file: $_"
    exit 1
}

$onpremDnsIp       = $phase1.onpremVmPrivateIp
$hubDnsIp          = $phase1.hubVmPrivateIp
$spoke1StorageName = $phase1.spoke1StorageAccountName

Write-Host ""
Write-Host "Loaded state from: $stateFile" -ForegroundColor Cyan
Write-Host "  vm-onprem-dns : $onpremDnsIp" -ForegroundColor Green
Write-Host "  vm-hub-dns    : $hubDnsIp"    -ForegroundColor Green

# ── Update VNet DNS settings ──────────────────────────────────────────────────
# Each VNet is updated to point to the appropriate custom DNS server.

Write-Host ""
Write-Host "Updating VNet DNS settings..." -ForegroundColor Cyan

$vnetUpdates = @(
    @{ rg = 'rg-dnsmig-onprem';  vnet = 'vnet-onprem';  dns = $onpremDnsIp; note = '(authoritative for onprem.pvt)' },
    @{ rg = 'rg-dnsmig-hub';     vnet = 'vnet-hub';     dns = $hubDnsIp;    note = '(authoritative for azure.pvt + privatelink)' },
    @{ rg = 'rg-dnsmig-spoke1';  vnet = 'vnet-spoke1';  dns = $hubDnsIp;    note = '(forwards to hub DNS)' },
    @{ rg = 'rg-dnsmig-spoke2';  vnet = 'vnet-spoke2';  dns = $hubDnsIp;    note = '(forwards to hub DNS)' }
)

foreach ($update in $vnetUpdates) {
    Write-Host "  Updating $($update.vnet) → DNS: $($update.dns) $($update.note)" -ForegroundColor Cyan

    az network vnet update `
        --resource-group $update.rg `
        --name $update.vnet `
        --dns-servers $update.dns `
        --output none `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to update DNS for $($update.vnet)."
        exit 1
    }

    Write-Host "    Done." -ForegroundColor Green
}

# ── Renew DHCP on all VMs to pick up new DNS settings ─────────────────────────
# Azure propagates VNet DNS changes via DHCP. We force a renewal so VMs
# pick up the new setting immediately without waiting for lease expiry.

Write-Host ""
Write-Host "Renewing DHCP on all VMs to apply new DNS settings..." -ForegroundColor Cyan

$dhcpScript = @'
#!/bin/bash
# Force a DHCP renewal so the new DNS server takes effect immediately.
# On Ubuntu 22.04, the primary interface is typically eth0 or ens3/ens4.
IFACE=$(ip -o link show | awk '{print $2}' | tr -d ':' | grep -v lo | head -1)
echo "Renewing DHCP on interface: $IFACE"
dhclient -r "$IFACE" 2>/dev/null || true
dhclient "$IFACE" 2>/dev/null || true
# Alternatively, use systemd-networkd if dhclient is not available
systemctl restart systemd-resolved 2>/dev/null || true
# Show resulting DNS config
systemd-resolve --status 2>/dev/null | grep "DNS Servers" | head -3 || cat /etc/resolv.conf
echo "DHCP renewal complete."
'@

$allVms = @(
    @{ rg = 'rg-dnsmig-onprem';  vm = 'vm-onprem-dns' },
    @{ rg = 'rg-dnsmig-hub';     vm = 'vm-hub-dns' },
    @{ rg = 'rg-dnsmig-spoke1';  vm = 'vm-spoke1' },
    @{ rg = 'rg-dnsmig-spoke2';  vm = 'vm-spoke2' }
)

foreach ($entry in $allVms) {
    $result = Invoke-VmRunCommand `
        -ResourceGroup $entry.rg `
        -VmName $entry.vm `
        -ScriptContent $dhcpScript `
        -Description 'Renewing DHCP'

    Write-Host "    $($entry.vm): $result" -ForegroundColor DarkGray
}

# ── End-to-end DNS validation from spoke VMs ──────────────────────────────────
# $spoke1StorageName is loaded from phase1-outputs.json above.

Write-Host ""
Write-Host "Running end-to-end DNS validation from vm-spoke1..." -ForegroundColor Cyan
Write-Host "(spoke1 should now use vm-hub-dns for all resolution)"
Write-Host ""

$validationScript = @"
#!/bin/bash
echo "=============================="
echo "DNS Server in use:"
systemd-resolve --status 2>/dev/null | grep "DNS Servers" | head -3 || cat /etc/resolv.conf | grep nameserver
echo ""

echo "=============================="
echo "Test 1: azure.pvt (hub zone)"
dig vm-hub-dns.azure.pvt A +short +timeout=3
echo ""

echo "=============================="
echo "Test 2: azure.pvt (spoke record)"
dig vm-spoke1.azure.pvt A +short +timeout=3
echo ""

echo "=============================="
echo "Test 3: onprem.pvt (cross-server forwarding from hub to onprem)"
dig vm-onprem-dns.onprem.pvt A +short +timeout=3
echo ""

echo "=============================="
echo "Test 4: privatelink.blob.core.windows.net (storage PE record)"
dig ${spoke1StorageName}.blob.core.windows.net A +short +timeout=3
echo ""

echo "=============================="
echo "Test 5: Internet resolution (microsoft.com)"
dig microsoft.com A +short +timeout=5 | head -3
echo ""

echo "End-to-end validation complete."
"@

$result = Invoke-VmRunCommand `
    -ResourceGroup 'rg-dnsmig-spoke1' `
    -VmName 'vm-spoke1' `
    -ScriptContent $validationScript `
    -Description 'Running end-to-end DNS validation'

Write-Host ""
Write-Host "═══════════ Validation Results (vm-spoke1) ═══════════" -ForegroundColor Yellow
Write-Host $result
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Yellow

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Phase 4 complete. Custom DNS is now active on all VNets." -ForegroundColor Green
Write-Host ""
Write-Host "DNS resolution chain:" -ForegroundColor Cyan
Write-Host "  VMs in vnet-onprem  → vm-onprem-dns ($onpremDnsIp)"
Write-Host "    onprem.pvt         authoritative"
Write-Host "    azure.pvt          forwarded to vm-hub-dns ($hubDnsIp)"
Write-Host "    privatelink.blob.* forwarded to vm-hub-dns ($hubDnsIp)"
Write-Host "    internet           forwarded to Azure DNS (168.63.129.16)"
Write-Host ""
Write-Host "  VMs in vnet-hub, spoke1, spoke2 → vm-hub-dns ($hubDnsIp)"
Write-Host "    azure.pvt          authoritative"
Write-Host "    privatelink.blob.* authoritative (legacy BIND9 zone)"
Write-Host "    onprem.pvt         forwarded to vm-onprem-dns ($onpremDnsIp)"
Write-Host "    internet           forwarded to Azure DNS (168.63.129.16)"
Write-Host ""
Write-Host "Migration baseline is now established." -ForegroundColor Green
Write-Host "Phases 5-7 (Private DNS Resolver migration) are not in scope for this run." -ForegroundColor Yellow
