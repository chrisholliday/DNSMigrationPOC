<#
.SYNOPSIS
    Phase 3 – Configure BIND9 DNS servers on the DNS VMs.

.DESCRIPTION
    Collects private IP addresses of all VMs and private endpoints, then
    pushes BIND9 zone configurations to both DNS VMs using az vm run-command.

    After this phase, DNS servers are configured and ready, but the VNets
    still point to Azure DNS (168.63.129.16).  The cutover happens in Phase 4.

    Zones configured:
      vm-onprem-dns  – authoritative for onprem.pvt
                     – forwards azure.pvt and privatelink.blob.* to vm-hub-dns
      vm-hub-dns     – authoritative for azure.pvt and privatelink.blob.core.windows.net
                     – forwards onprem.pvt to vm-onprem-dns

.EXAMPLE
    .\configure-dns.ps1

.NOTES
    Prerequisite: Phases 1 and 2 must be deployed.
    Run 'az login' and 'az account set --subscription <id>' before executing.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: run az vm run-command and return stdout ───────────────────────────

function Invoke-VmRunCommand {
    [CmdletBinding()]
    param(
        [string] $ResourceGroup,
        [string] $VmName,
        [string] $ScriptContent,
        [string] $Description
    )

    Write-Host "  [$VmName] $Description..." -ForegroundColor Cyan

    # Write script to a temp file to avoid shell escaping issues
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
        $stderr = $parsed.value | Where-Object { $_.code -like '*StdErr*' } | Select-Object -ExpandProperty message

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Verbose "  [$VmName] stderr: $stderr"
        }

        return $stdout
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

# ── Verify Azure CLI login ─────────────────────────────────────────────────────

Write-Host 'Verifying Azure CLI authentication...' -ForegroundColor Cyan
$account = az account show --output json 2>&1 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}
Write-Host "  Subscription: $($account.name)" -ForegroundColor Green

# ── Load Phase 1 state file ───────────────────────────────────────────────────

$stateFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'phase1-outputs.json'

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

$onpremDnsIp      = $phase1.onpremVmPrivateIp
$hubDnsIp         = $phase1.hubVmPrivateIp
$spoke1VmIp       = $phase1.spoke1VmPrivateIp
$spoke2VmIp       = $phase1.spoke2VmPrivateIp
$spoke1StorageName = $phase1.spoke1StorageAccountName
$spoke2StorageName = $phase1.spoke2StorageAccountName

Write-Host ''
Write-Host "Loaded state from: $stateFile" -ForegroundColor Cyan
Write-Host "  vm-onprem-dns IP : $onpremDnsIp" -ForegroundColor Green
Write-Host "  vm-hub-dns IP    : $hubDnsIp"    -ForegroundColor Green
Write-Host "  vm-spoke1 IP     : $spoke1VmIp"  -ForegroundColor Green
Write-Host "  vm-spoke2 IP     : $spoke2VmIp"  -ForegroundColor Green
Write-Host "  Spoke1 storage   : $spoke1StorageName" -ForegroundColor Green
Write-Host "  Spoke2 storage   : $spoke2StorageName" -ForegroundColor Green

# ── Collect Private Endpoint IPs ──────────────────────────────────────────────

Write-Host ''
Write-Host 'Collecting private endpoint IPs...' -ForegroundColor Cyan

function Get-PrivateEndpointIp {
    param([string] $ResourceGroup, [string] $PeName)

    $nicId = az network private-endpoint show `
        --resource-group $ResourceGroup `
        --name $PeName `
        --query 'networkInterfaces[0].id' `
        --output tsv `
        --only-show-errors 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nicId)) {
        Write-Error "Could not find private endpoint '$PeName' in '$ResourceGroup'."
        return $null
    }

    $ip = az network nic show `
        --ids $nicId `
        --query 'ipConfigurations[0].privateIPAddress' `
        --output tsv `
        --only-show-errors 2>&1

    return $ip.Trim()
}

$spoke1PeIp = Get-PrivateEndpointIp `
    -ResourceGroup 'rg-dnsmig-spoke1' `
    -PeName "${spoke1StorageName}-pe-blob"

$spoke2PeIp = Get-PrivateEndpointIp `
    -ResourceGroup 'rg-dnsmig-spoke2' `
    -PeName "${spoke2StorageName}-pe-blob"

if ([string]::IsNullOrWhiteSpace($spoke1PeIp) -or [string]::IsNullOrWhiteSpace($spoke2PeIp)) {
    Write-Error 'Could not collect private endpoint IPs.'
    exit 1
}

Write-Host "  Spoke1 PE IP     : $spoke1PeIp" -ForegroundColor Green
Write-Host "  Spoke2 PE IP     : $spoke2PeIp" -ForegroundColor Green

# ══════════════════════════════════════════════════════════════════════════════
# Configure vm-onprem-dns
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host 'Configuring vm-onprem-dns (onprem.pvt zone)...' -ForegroundColor Cyan

$onpremDnsScript = @"
#!/bin/bash
set -e

# ── Create zone directory ──────────────────────────────────────────────────
mkdir -p /etc/bind/zones

# ── named.conf.options ────────────────────────────────────────────────────
cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { any; };

    // Default forwarder: send unmatched queries to Azure DNS
    forwarders { 168.63.129.16; };
    forward only;

    dnssec-validation no;
    listen-on { any; };
};
EOF

# ── named.conf.local ──────────────────────────────────────────────────────
cat > /etc/bind/named.conf.local << EOF
// Authoritative zone: onprem.pvt
zone "onprem.pvt" {
    type master;
    file "/etc/bind/zones/db.onprem.pvt";
};

// Conditional forward: azure.pvt -> vm-hub-dns
zone "azure.pvt" {
    type forward;
    forward only;
    forwarders { $hubDnsIp; };
};

// Conditional forward: privatelink.blob.core.windows.net -> vm-hub-dns
zone "privatelink.blob.core.windows.net" {
    type forward;
    forward only;
    forwarders { $hubDnsIp; };
};
EOF

# ── Zone file: onprem.pvt ─────────────────────────────────────────────────
cat > /etc/bind/zones/db.onprem.pvt << 'ZONE_EOF'
`$TTL    300
@       IN      SOA     vm-onprem-dns.onprem.pvt. admin.onprem.pvt. (
                            1         ; serial
                            300       ; refresh
                            60        ; retry
                            3600      ; expire
                            300 )     ; negative TTL
;
@               IN      NS      vm-onprem-dns.onprem.pvt.
;
; A Records
vm-onprem-dns   IN      A       $onpremDnsIp
ZONE_EOF

# ── Validate config and restart BIND ─────────────────────────────────────
named-checkconf /etc/bind/named.conf
named-checkzone onprem.pvt /etc/bind/zones/db.onprem.pvt
systemctl restart named
systemctl is-active named
echo "vm-onprem-dns BIND configuration complete."
"@

$result = Invoke-VmRunCommand `
    -ResourceGroup 'rg-dnsmig-onprem' `
    -VmName 'vm-onprem-dns' `
    -ScriptContent $onpremDnsScript `
    -Description 'Applying BIND9 configuration'

Write-Host "  Output: $result" -ForegroundColor DarkGray

# ══════════════════════════════════════════════════════════════════════════════
# Configure vm-hub-dns
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host 'Configuring vm-hub-dns (azure.pvt and privatelink.blob zones)...' -ForegroundColor Cyan

$hubDnsScript = @"
#!/bin/bash
set -e

# ── Create zone directory ──────────────────────────────────────────────────
mkdir -p /etc/bind/zones

# ── named.conf.options ────────────────────────────────────────────────────
cat > /etc/bind/named.conf.options << 'EOF'
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { any; };

    // Default forwarder: send unmatched queries to Azure DNS
    forwarders { 168.63.129.16; };
    forward only;

    dnssec-validation no;
    listen-on { any; };
};
EOF

# ── named.conf.local ──────────────────────────────────────────────────────
cat > /etc/bind/named.conf.local << EOF
// Authoritative zone: azure.pvt
zone "azure.pvt" {
    type master;
    file "/etc/bind/zones/db.azure.pvt";
};

// Authoritative zone: privatelink.blob.core.windows.net (legacy before Phase 5)
zone "privatelink.blob.core.windows.net" {
    type master;
    file "/etc/bind/zones/db.privatelink.blob";
};

// Conditional forward: onprem.pvt -> vm-onprem-dns
zone "onprem.pvt" {
    type forward;
    forward only;
    forwarders { $onpremDnsIp; };
};
EOF

# ── Zone file: azure.pvt ──────────────────────────────────────────────────
cat > /etc/bind/zones/db.azure.pvt << 'ZONE_EOF'
`$TTL    300
@       IN      SOA     vm-hub-dns.azure.pvt. admin.azure.pvt. (
                            1         ; serial
                            300       ; refresh
                            60        ; retry
                            3600      ; expire
                            300 )     ; negative TTL
;
@           IN      NS      vm-hub-dns.azure.pvt.
;
; A Records
vm-hub-dns  IN      A       $hubDnsIp
vm-spoke1   IN      A       $spoke1VmIp
vm-spoke2   IN      A       $spoke2VmIp
ZONE_EOF

# ── Zone file: privatelink.blob.core.windows.net ──────────────────────────
cat > /etc/bind/zones/db.privatelink.blob << 'ZONE_EOF'
`$TTL    300
@       IN      SOA     vm-hub-dns.azure.pvt. admin.azure.pvt. (
                            1         ; serial
                            300       ; refresh
                            60        ; retry
                            3600      ; expire
                            300 )     ; negative TTL
;
@               IN      NS      vm-hub-dns.azure.pvt.
;
; Storage account private endpoint A Records
$spoke1StorageName    IN      A       $spoke1PeIp
$spoke2StorageName    IN      A       $spoke2PeIp
ZONE_EOF

# ── Validate config and restart BIND ─────────────────────────────────────
named-checkconf /etc/bind/named.conf
named-checkzone azure.pvt /etc/bind/zones/db.azure.pvt
named-checkzone privatelink.blob.core.windows.net /etc/bind/zones/db.privatelink.blob
systemctl restart named
systemctl is-active named
echo "vm-hub-dns BIND configuration complete."
"@

$result = Invoke-VmRunCommand `
    -ResourceGroup 'rg-dnsmig-hub' `
    -VmName 'vm-hub-dns' `
    -ScriptContent $hubDnsScript `
    -Description 'Applying BIND9 configuration'

Write-Host "  Output: $result" -ForegroundColor DarkGray

# ══════════════════════════════════════════════════════════════════════════════
# Validate: query DNS servers directly
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host 'Validating DNS resolution by querying servers directly...' -ForegroundColor Cyan
Write-Host '(VNets still use Azure DNS; these queries go directly to each server)'
Write-Host ''

# Query onprem-dns directly for its own zone
$testOnpremScript = @'
#!/bin/bash
echo "=== Testing vm-onprem-dns (querying itself) ==="
dig @127.0.0.1 vm-onprem-dns.onprem.pvt A +short
echo "=== Forwarding test: azure.pvt via hub ==="
dig @127.0.0.1 vm-hub-dns.azure.pvt A +short
echo "=== Forwarding test: internet ==="
dig @127.0.0.1 microsoft.com A +short | head -3
'@

$result = Invoke-VmRunCommand `
    -ResourceGroup 'rg-dnsmig-onprem' `
    -VmName 'vm-onprem-dns' `
    -ScriptContent $testOnpremScript `
    -Description 'Running DNS resolution tests'

Write-Host ''
Write-Host '  vm-onprem-dns test results:' -ForegroundColor Yellow
Write-Host $result

# Query hub-dns directly for its zones
$testHubScript = @"
#!/bin/bash
echo "=== Testing vm-hub-dns: azure.pvt ==="
dig @127.0.0.1 vm-hub-dns.azure.pvt A +short
dig @127.0.0.1 vm-spoke1.azure.pvt A +short
dig @127.0.0.1 vm-spoke2.azure.pvt A +short
echo "=== Testing vm-hub-dns: privatelink zone ==="
dig @127.0.0.1 $spoke1StorageName.blob.core.windows.net A +short
echo "=== Forwarding test: onprem.pvt ==="
dig @127.0.0.1 vm-onprem-dns.onprem.pvt A +short
echo "=== Forwarding test: internet ==="
dig @127.0.0.1 microsoft.com A +short | head -3
"@

$result = Invoke-VmRunCommand `
    -ResourceGroup 'rg-dnsmig-hub' `
    -VmName 'vm-hub-dns' `
    -ScriptContent $testHubScript `
    -Description 'Running DNS resolution tests'

Write-Host ''
Write-Host '  vm-hub-dns test results:' -ForegroundColor Yellow
Write-Host $result

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host 'Phase 3 complete.' -ForegroundColor Green
Write-Host ''
Write-Host 'DNS servers are configured and serving zones.' -ForegroundColor Green
Write-Host 'VNets still use Azure DNS (168.63.129.16).' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Next step: Run phase4\deploy-phase4.ps1 to switch VNets to custom DNS.' -ForegroundColor Cyan
