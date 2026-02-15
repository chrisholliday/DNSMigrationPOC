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
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true

# Install dnsmasq if not already installed
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update > /dev/null 2>&1
    apt-get install -y dnsmasq > /dev/null 2>&1
fi

# Create dnsmasq config
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
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf || true

# Start dnsmasq
systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq
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
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true

# Install dnsmasq if not already installed
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update > /dev/null 2>&1
    apt-get install -y dnsmasq > /dev/null 2>&1
fi

# Create dnsmasq config
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/azure.conf <<'EOF'
port=53
listen-address=10.20.1.4
address=/azure.pvt/10.20.1.4
address=/privatelink.blob.core.windows.net/10.20.1.4
EOF

# Update resolv.conf (use loopback since dnsmasq is also local)
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf || true

# Start dnsmasq
systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq
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
$result = Invoke-AzVMRunCommand `
    -ResourceGroupName $rgOnprem `
    -VMName "$Prefix-onprem-vm-dns" `
    -CommandId 'RunShellScript' `
    -ScriptString $onpremDnsScript `
    -ErrorAction SilentlyContinue

$message = $result.Value[0].Message
if ($message -match 'configured' -and $result.ReturnCode -eq 0) {
    Write-Host '  ✓ On-prem DNS configured'
}
else {
    Write-Host "  ! On-prem DNS configuration failed (exit $($result.ReturnCode))"
    Write-Host $message
}

# Configure Hub DNS Server
Write-Host "`nConfiguring Hub DNS Server..."
Write-Host '  Installing dnsmasq and setting up zones...'
$result = Invoke-AzVMRunCommand `
    -ResourceGroupName $rgHub `
    -VMName "$Prefix-hub-vm-dns" `
    -CommandId 'RunShellScript' `
    -ScriptString $hubDnsScript `
    -ErrorAction SilentlyContinue

$message = $result.Value[0].Message
if ($message -match 'configured' -and $result.ReturnCode -eq 0) {
    Write-Host '  ✓ Hub DNS configured'
}
else {
    Write-Host "  ! Hub DNS configuration failed (exit $($result.ReturnCode))"
    Write-Host $message
}

Write-Host ''
Write-Host '=================================================='
Write-Host '✓ DNS Server Configuration Complete!'
Write-Host '=================================================='
Write-Host ''
Write-Host 'DNS Servers are ready for testing.'
Write-Host ''
Write-Host "Next: Run './scripts/validate.ps1 -Phase Legacy' to test DNS resolution"
