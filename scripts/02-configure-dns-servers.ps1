param(
    [string]$Prefix = 'dnsmig'
)

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"

Write-Host '=================================================='
Write-Host 'Configuring DNS Servers'
Write-Host '=================================================='

# Script to setup dnsmasq on On-Prem DNS
$onpremDnsScript = @'
#!/bin/bash
set -e

# Stop systemd-resolved which owns port 53 by default
echo "Stopping systemd-resolved..."
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true

# Install dnsmasq-base
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update
    apt-get install -y dnsmasq-base
    if ! command -v dnsmasq &> /dev/null; then
        echo "ERROR: dnsmasq installation failed"
        exit 1
    fi
fi

# Create dnsmasq config
echo "Creating dnsmasq config..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/onprem.conf <<'EOF'
port=53
listen-address=10.10.1.4
address=/onprem.pvt/10.10.1.4
address=/azure.pvt/10.20.1.4
address=/privatelink.blob.core.windows.net/10.20.1.4
server=/azure.pvt/10.20.1.4#53
server=/privatelink.blob.core.windows.net/10.20.1.4#53
EOF

# Update resolv.conf (use loopback since dnsmasq is also local)
echo "Updating resolv.conf..."
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf || true

# Start dnsmasq
echo "Starting dnsmasq..."
systemctl restart dnsmasq || systemctl start dnsmasq
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start dnsmasq"
    systemctl --no-pager status dnsmasq || true
    exit 1
fi
systemctl enable dnsmasq

# Verify dnsmasq is running
if ! systemctl is-active --quiet dnsmasq; then
  echo "ERROR: dnsmasq failed to start"
  systemctl --no-pager status dnsmasq
  exit 1
fi

# Verify port 53 is listening
if ! ss -tlnp | grep -q ':53'; then
  echo "ERROR: no service listening on port 53"
  ss -tlnp | grep dnsmasq || true
  exit 1
fi

echo "On-prem DNS configured"
'@

# Script to setup dnsmasq on Hub DNS
$hubDnsScript = @'
#!/bin/bash
set -e

# Stop systemd-resolved which owns port 53 by default
echo "Stopping systemd-resolved..."
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true

# Install dnsmasq-base
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update
    apt-get install -y dnsmasq-base
    if ! command -v dnsmasq &> /dev/null; then
        echo "ERROR: dnsmasq installation failed"
        exit 1
    fi
fi

# Create dnsmasq config
echo "Creating dnsmasq config..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/azure.conf <<'EOF'
port=53
listen-address=10.20.1.4
address=/azure.pvt/10.20.1.4
address=/privatelink.blob.core.windows.net/10.20.1.4
EOF

# Update resolv.conf (use loopback since dnsmasq is also local)
echo "Updating resolv.conf..."
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf || true

# Start dnsmasq
echo "Starting dnsmasq..."
systemctl restart dnsmasq || systemctl start dnsmasq
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start dnsmasq"
    systemctl --no-pager status dnsmasq || true
    exit 1
fi
systemctl enable dnsmasq

# Verify dnsmasq is running
if ! systemctl is-active --quiet dnsmasq; then
  echo "ERROR: dnsmasq failed to start"
  systemctl --no-pager status dnsmasq
  exit 1
fi

# Verify port 53 is listening
if ! ss -tlnp | grep -q ':53'; then
  echo "ERROR: no service listening on port 53"
  ss -tlnp | grep dnsmasq || true
  exit 1
fi

echo "Hub DNS configured"
'@

# Configure On-Prem DNS Server
Write-Host "`nConfiguring On-Prem DNS Server..."
Write-Host '  Installing dnsmasq and setting up zones...'
try {
    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rgOnprem `
        -VMName "$Prefix-onprem-vm-dns" `
        -CommandId 'RunShellScript' `
        -ScriptString $onpremDnsScript `
        -ErrorAction Stop `
        -WarningAction SilentlyContinue

    if ($null -eq $result -or $null -eq $result.Value -or $result.Value.Count -eq 0) {
        Write-Host '  ✗ No output from VM command execution' -ForegroundColor Red
        exit 1
    }

    $message = $result.Value[0].Message
    $exitCode = $result.Value[0].ExitCode
    
    Write-Host "Exit code: $exitCode"
    Write-Host 'Output:'
    Write-Host $message
    
    if ($exitCode -eq 0) {
        Write-Host '  ✓ On-prem DNS server configured successfully'
    }
    else {
        Write-Host "  ✗ On-prem DNS configuration failed with exit code $exitCode" -ForegroundColor Red
        Write-Host 'Script output:' -ForegroundColor Red
        Write-Host $message -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "  ✗ Exception running configuration: $_" -ForegroundColor Red
    exit 1
}

# Configure Hub DNS Server
Write-Host "`nConfiguring Hub DNS Server..."
Write-Host '  Installing dnsmasq and setting up zones...'
try {
    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rgHub `
        -VMName "$Prefix-hub-vm-dns" `
        -CommandId 'RunShellScript' `
        -ScriptString $hubDnsScript `
        -ErrorAction Stop `
        -WarningAction SilentlyContinue

    if ($null -eq $result -or $null -eq $result.Value -or $result.Value.Count -eq 0) {
        Write-Host '  ✗ No output from VM command execution' -ForegroundColor Red
        exit 1
    }

    $message = $result.Value[0].Message
    $exitCode = $result.Value[0].ExitCode
    
    Write-Host "Exit code: $exitCode"
    Write-Host 'Output:'
    Write-Host $message
    
    if ($exitCode -eq 0) {
        Write-Host '  ✓ Hub DNS server configured successfully'
    }
    else {
        Write-Host "  ✗ Hub DNS configuration failed with exit code $exitCode" -ForegroundColor Red
        Write-Host 'Script output:' -ForegroundColor Red
        Write-Host $message -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "  ✗ Exception running configuration: $_" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '=================================================='
Write-Host '✓ DNS Server Configuration Complete!'
Write-Host '=================================================='
Write-Host ''
Write-Host 'DNS Servers are ready for testing.'
Write-Host ''
Write-Host "Next: Run './scripts/validate.ps1 -Phase Legacy' to test DNS resolution"
