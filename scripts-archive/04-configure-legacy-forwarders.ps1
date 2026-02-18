param(
    [string]$Prefix = 'dnsmig'
)

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"

Write-Host "=================================================="
Write-Host "Phase 3: Configure Legacy Forwarders"
Write-Host "=================================================="

# Get inbound resolver IP from Private Resolver
Write-Host "\nRetrieving Private Resolver inbound endpoint IP..."
$resolver = Get-AzResource -ResourceGroupName $rgHub -ResourceType 'Microsoft.Network/dnsResolvers' -ErrorAction SilentlyContinue
if (-not $resolver) {
    Write-Error "DNS Resolver not found in $rgHub. Please run 03-deploy-private-dns.ps1 first."
    exit 1
}

$inboundEndpoint = Get-AzResource -ResourceGroupName $rgHub -ResourceType 'Microsoft.Network/dnsResolvers/inboundEndpoints' -ErrorAction SilentlyContinue
if (-not $inboundEndpoint) {
    Write-Error "Inbound endpoint not found. DNS Resolver deployment may be incomplete."
    exit 1
}

$inboundNic = Get-AzNetworkInterface -ResourceGroupName $rgHub -Name "$Prefix-resolver-inbound-nic" -ErrorAction SilentlyContinue
if (-not $inboundNic) {
    Write-Host "  ! Inbound NIC not found, using default IP 10.20.2.4"
    $InboundResolverIp = '10.20.2.4'
} else {
    $InboundResolverIp = $inboundNic.IpConfigurations[0].PrivateIpAddress
    Write-Host "  ✓ Inbound resolver IP: $InboundResolverIp"
}

# Script to update forwarders on DNS VMs
$updateScript = @"
#!/bin/bash
set -e

# Remove old privatelink forward rule if it exists
rm -f /etc/dnsmasq.d/privatelink-forward.conf 2>/dev/null || true

# Add new forward rule to inbound resolver
echo "server=/privatelink.blob.core.windows.net/$InboundResolverIp" > /etc/dnsmasq.d/privatelink-forward.conf

# Restart dnsmasq
systemctl restart dnsmasq

echo "Forwarder configured for privatelink.blob.core.windows.net → $InboundResolverIp"
"@

Write-Host "\nUpdating on-prem DNS forwarder..."
try {
    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rgOnprem `
        -VMName "$Prefix-onprem-vm-dns" `
        -CommandId 'RunShellScript' `
        -ScriptString $updateScript `
        -ErrorAction Stop `
        -WarningAction SilentlyContinue

    if ($result.Value[0].Message -match 'Forwarder configured') {
        Write-Host "  ✓ On-prem forwarder updated"
    } else {
        Write-Host "  ! Status: $($result.Value[0].Message | Select-Object -First 100)"
    }
} catch {
    Write-Host "  ✗ Error updating on-prem forwarder: $_" -ForegroundColor Red
    exit 1
}

Write-Host "\nUpdating hub DNS forwarder..."
try {
    $result = Invoke-AzVMRunCommand `
        -ResourceGroupName $rgHub `
        -VMName "$Prefix-hub-vm-dns" `
        -CommandId 'RunShellScript' `
        -ScriptString $updateScript `
        -ErrorAction Stop `
        -WarningAction SilentlyContinue

    if ($result.Value[0].Message -match 'Forwarder configured') {
        Write-Host "  ✓ Hub forwarder updated"
    } else {
        Write-Host "  ! Status: $($result.Value[0].Message | Select-Object -First 100)"
    }
} catch {
    Write-Host "  ✗ Error updating hub forwarder: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=================================================="
Write-Host "✓ Phase 3 Complete: Forwarders Updated"
Write-Host "=================================================="
Write-Host ""
Write-Host "Legacy DNS servers now forward privatelink.blob.core.windows.net"
Write-Host "to the Private Resolver inbound endpoint ($InboundResolverIp)"
Write-Host ""
Write-Host "Next: Validate DNS resolution with './scripts/validate.ps1 -Phase AfterForwarders'"
