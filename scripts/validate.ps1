param(
    [string]$Prefix = 'dnsmig',
    [ValidateSet('Legacy', 'AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')][string]$Phase = 'AfterSpoke2'
)

if (-not $PSBoundParameters.ContainsKey('Phase')) {
    Write-Host 'Select validation phase:'
    Write-Host '  1) Legacy'
    Write-Host '  2) AfterPrivateDns'
    Write-Host '  3) AfterForwarders'
    Write-Host '  4) AfterSpoke1'
    Write-Host '  5) AfterSpoke2'

    $selection = Read-Host 'Enter 1-5'
    switch ($selection) {
        '1' { $Phase = 'Legacy' }
        '2' { $Phase = 'AfterPrivateDns' }
        '3' { $Phase = 'AfterForwarders' }
        '4' { $Phase = 'AfterSpoke1' }
        '5' { $Phase = 'AfterSpoke2' }
        default {
            Write-Host "Invalid selection '$selection'. Using default: $Phase" -ForegroundColor Yellow
        }
    }
}

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"
$rgSpoke1 = "$Prefix-rg-spoke1"
$rgSpoke2 = "$Prefix-rg-spoke2"

# VM names (hardcoded from Bicep deployment)
$onpremDnsVm = "$Prefix-onprem-vm-dns"
$onpremClientVm = "$Prefix-onprem-vm-client"
$hubDnsVm = "$Prefix-hub-vm-dns"
$spoke1Vm = "$Prefix-spoke1-vm-app"
$spoke2Vm = "$Prefix-spoke2-vm-app"

function Invoke-RunCmd {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Script
    )
    Write-Host "  - Testing $VmName..."

    $wrappedScript = @"
set -o pipefail
$Script
__COMMAND_EXIT_CODE__:$?
"@

    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VmName -CommandId 'RunShellScript' -ScriptString $wrappedScript -ErrorAction Stop
        $message = ($result.Value[0].Message | Out-String).Trim()
        $exitCode = $null

        if ($message -match '__COMMAND_EXIT_CODE__:(\d+)') {
            $exitCode = [int]$Matches[1]
        }

        $cleanMessage = ($message -replace '__COMMAND_EXIT_CODE__:\d+', '').Trim()

        # Explicit failure detection
        if ($null -eq $exitCode) {
            Write-Host "    ✗ Failed to extract exit code from output" -ForegroundColor Red
            Write-Host "    Output: $message" -ForegroundColor Red
            return [pscustomobject]@{ Vm = $VmName; Success = $false; Details = "Could not determine exit code: $message" }
        }

        if ($exitCode -ne 0) {
            Write-Host "    ✗ Command failed with exit code $exitCode" -ForegroundColor Red
            Write-Host "    Details:" -ForegroundColor Red
            $cleanMessage -split "`n" | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
            return [pscustomobject]@{ Vm = $VmName; Success = $false; Details = $cleanMessage }
        }

        Write-Host "    ✓ Passed"
        return [pscustomobject]@{ Vm = $VmName; Success = $true; Details = $cleanMessage }
    }
    catch {
        Write-Host "    ✗ Exception while running command: $_" -ForegroundColor Red
        return [pscustomobject]@{ Vm = $VmName; Success = $false; Details = $_.Exception.Message }
    }
}

function Get-DnsDiagnostics {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $diagScript = @'
#!/bin/bash
echo "--- dnsmasq diagnostics ---"
if command -v dnsmasq >/dev/null 2>&1; then
    echo "dnsmasq installed: yes"
else
    echo "dnsmasq installed: no"
fi

if systemctl is-active --quiet dnsmasq; then
    echo "dnsmasq running: yes"
else
    echo "dnsmasq running: no"
    systemctl --no-pager status dnsmasq || true
fi

echo "listening on 53:" 
ss -tlnp | grep ':53' || true

echo "resolv.conf:"
cat /etc/resolv.conf || true

echo "dnsmasq config files:"
ls -1 /etc/dnsmasq.d || true
'@

    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VmName -CommandId 'RunShellScript' -ScriptString $diagScript -ErrorAction Stop
        return ($result.Value[0].Message | Out-String).Trim()
    }
    catch {
        return "Failed to collect diagnostics: $($_.Exception.Message)"
    }
}


Write-Host '=================================================='
Write-Host "Validation: Phase $Phase"
Write-Host '=================================================='
Write-Host ''

Write-Host 'Testing DNS resolution on all VMs...'
$basicOnpremDns = @'
#!/bin/bash
fail=0

if ! command -v dig >/dev/null 2>&1; then
    echo "dig not installed"
    exit 2
fi

if ! systemctl is-active --quiet dnsmasq; then
    echo "dnsmasq is not running"
    systemctl --no-pager status dnsmasq || true
    exit 1
fi

check() {
    name=$1
    server=$2
    out=$(dig +short @$server "$name")
    if [ -z "$out" ]; then
        echo "FAIL: $name"
        fail=1
    else
        echo "OK: $name -> $out"
    fi
}

check onprem-vm-client.onprem.pvt 127.0.0.1
check spoke1-vm-app.azure.pvt 127.0.0.1

exit $fail
'@

$basicHubDns = @'
#!/bin/bash
fail=0

if ! command -v dig >/dev/null 2>&1; then
    echo "dig not installed"
    exit 2
fi

if ! systemctl is-active --quiet dnsmasq; then
    echo "dnsmasq is not running"
    systemctl --no-pager status dnsmasq || true
    exit 1
fi

check() {
    name=$1
    server=$2
    out=$(dig +short @$server "$name")
    if [ -z "$out" ]; then
        echo "FAIL: $name"
        fail=1
    else
        echo "OK: $name -> $out"
    fi
}

check onprem-vm-dns.onprem.pvt 127.0.0.1
check spoke1-vm-app.azure.pvt 127.0.0.1

exit $fail
'@

$basicSpoke = @'
#!/bin/bash
fail=0

if ! command -v dig >/dev/null 2>&1; then
    echo "dig not installed"
    exit 2
fi

check() {
    name=$1
    out=$(dig +short "$name")
    if [ -z "$out" ]; then
        echo "FAIL: $name"
        fail=1
    else
        echo "OK: $name -> $out"
    fi
}

check onprem-vm-client.onprem.pvt
check spoke1-vm-app.azure.pvt

exit $fail
'@

$dnsResults = @()
$dnsResults += Invoke-RunCmd -ResourceGroup $rgOnprem -VmName $onpremDnsVm -Script $basicOnpremDns
$dnsResults += Invoke-RunCmd -ResourceGroup $rgHub -VmName $hubDnsVm -Script $basicHubDns
$dnsResults += Invoke-RunCmd -ResourceGroup $rgSpoke1 -VmName $spoke1Vm -Script $basicSpoke
$dnsResults += Invoke-RunCmd -ResourceGroup $rgSpoke2 -VmName $spoke2Vm -Script $basicSpoke

$dnsFailures = $dnsResults | Where-Object { -not $_.Success }
if ($dnsFailures.Count -gt 0) {
    Write-Host ''
    Write-Host 'DNS resolution failures detected:' -ForegroundColor Red
    $dnsFailures | ForEach-Object {
        Write-Host "  ✗ $($_.Vm)" -ForegroundColor Red
        if ($_.Details) {
            $_.Details -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }

        if ($_.Vm -in @($onpremDnsVm, $hubDnsVm)) {
            Write-Host "    Running detailed diagnostics:" -ForegroundColor Red
            $diag = Get-DnsDiagnostics -ResourceGroup ($_.Vm -eq $onpremDnsVm ? $rgOnprem : $rgHub) -VmName $_.Vm
            $diag -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }
    }
    Write-Host ''
    Write-Host '❌ Validation FAILED - DNS is not properly configured' -ForegroundColor Red
    exit 1
}
else {
    Write-Host ''
    Write-Host '✓ DNS resolution succeeded on all VMs.'
}

if ($Phase -in @('AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')) {
    Write-Host ''
    Write-Host 'Checking Private DNS zone records...'

    $privateZoneName = 'privatelink.blob.core.windows.net'
    $privateZone = Get-AzPrivateDnsZone -Name $privateZoneName -ResourceGroupName $rgHub -ErrorAction SilentlyContinue

    if (-not $privateZone) {
        Write-Host "  ! Private DNS zone '$privateZoneName' not found in $rgHub. Skipping record check." -ForegroundColor Yellow
    }
    else {
        try {
            Get-AzPrivateDnsRecordSet -ZoneName $privateZoneName -ResourceGroupName $rgHub -RecordType A |
                Select-Object -First 5 |
                Format-Table
        }
        catch {
            Write-Host "  ! Failed to read records from '$privateZoneName'. $_" -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host "✓ Validation complete for phase: $Phase"