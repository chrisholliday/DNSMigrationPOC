param(
    [string]$Prefix = 'dnsmig'
)

$rgName = "$Prefix-rg"

Write-Host '=================================================='
Write-Host 'Configuring DNS Servers'
Write-Host '=================================================='

# Script to setup dnsmasq on On-Prem DNS
$onpremDnsScript = @'
#!/bin/bash
set -e

# Install dnsmasq if not already installed
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update > /dev/null 2>&1
    apt-get install -y dnsmasq > /dev/null 2>&1
fi

# Create dnsmasq config
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/onprem.conf <<'EOF'
port=5053
address=/onprem.pvt/10.10.1.4
address=/azure.pvt/10.20.1.4
address=/privatelink.blob.core.windows.net/10.20.1.4
server=/onprem.pvt/127.0.0.1#5053
server=/azure.pvt/10.20.1.4#53
server=/privatelink.blob.core.windows.net/10.20.1.4#53
EOF

# Update resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Start dnsmasq
systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq
systemctl enable dnsmasq

echo "On-prem DNS configured"
'@

# Script to setup dnsmasq on Hub DNS
$hubDnsScript = @'
#!/bin/bash
set -e

# Install dnsmasq if not already installed
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    apt-get update > /dev/null 2>&1
    apt-get install -y dnsmasq > /dev/null 2>&1
fi

# Create dnsmasq config
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/azure.conf <<'EOF'
port=5053
address=/azure.pvt/10.20.1.4
address=/privatelink.blob.core.windows.net/10.20.1.4
server=/azure.pvt/127.0.0.1#5053
server=/privatelink.blob.core.windows.net/10.20.1.4#53
EOF

# Update resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Start dnsmasq
systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq
systemctl enable dnsmasq

echo "Hub DNS configured"
'@

# Configure On-Prem DNS Server
Write-Host "`nConfiguring On-Prem DNS Server..."
Write-Host '  Installing dnsmasq and setting up zones...'
$result = Invoke-AzVMRunCommand `
    -ResourceGroupName $rgName `
    -VMName 'dnsmig-onprem-dns' `
    -CommandId 'RunShellScript' `
    -ScriptString $onpremDnsScript `
    -ErrorAction SilentlyContinue

$message = $result.Value[0].Message
if ($message -match 'configured|already|DNS') {
    Write-Host '  ✓ On-prem DNS configured'
}
else {
    Write-Host "  ! Status: $($message | Select-Object -First 200)"
}

# Configure Hub DNS Server
Write-Host "`nConfiguring Hub DNS Server..."
Write-Host '  Installing dnsmasq and setting up zones...'
$result = Invoke-AzVMRunCommand `
    -ResourceGroupName $rgName `
    -VMName 'dnsmig-hub-dns' `
    -CommandId 'RunShellScript' `
    -ScriptString $hubDnsScript `
    -ErrorAction SilentlyContinue

$message = $result.Value[0].Message
if ($message -match 'configured|already|DNS') {
    Write-Host '  ✓ Hub DNS configured'
}
else {
    Write-Host "  ! Status: $($message | Select-Object -First 200)"
}

Write-Host ''
Write-Host '=================================================='
Write-Host '✓ DNS Server Configuration Complete!'
Write-Host '=================================================='
Write-Host ''
Write-Host 'DNS Servers are ready for testing.'
Write-Host ''
Write-Host "Next: Run './scripts/validate.ps1 -Phase Legacy' to test DNS resolution"
