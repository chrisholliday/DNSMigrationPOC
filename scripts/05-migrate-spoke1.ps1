param(
    [string]$Prefix = 'dnsmig'
)

$rgSpoke1 = "$Prefix-rg-spoke1"

Write-Host "=================================================="
Write-Host "Phase 4: Migrate Spoke1 to Azure DNS"
Write-Host "=================================================="

Write-Host "\nSwitching Spoke1 VNet to Azure-provided DNS..."
$vnet = Get-AzVirtualNetwork -ResourceGroupName $rgSpoke1 -Name "$Prefix-spoke1-vnet"
$vnet.DhcpOptions.DnsServers = @()
Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null

Write-Host "  ✓ Spoke1 VNet DNS servers cleared"
Write-Host ""
Write-Host "=================================================="
Write-Host "✓ Phase 4 Complete: Spoke1 Migrated"
Write-Host "=================================================="
Write-Host ""
Write-Host "Spoke1 VMs will now use Azure-provided DNS which resolves"
Write-Host "privatelink.blob.core.windows.net via the Private Resolver."
Write-Host ""
Write-Host "Next: Validate DNS resolution with './scripts/validate.ps1 -Phase AfterSpoke1'"
