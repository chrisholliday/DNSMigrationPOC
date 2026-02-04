param(
    [string]$Prefix = 'dnsmig'
)

$rgName = "$Prefix-rg"

Write-Host "=================================================="
Write-Host "Phase 5: Migrate Spoke2 to Azure DNS"
Write-Host "=================================================="

Write-Host "\nLinking Spoke2 VNet to Private DNS zone..."
$privateDnsZone = Get-AzPrivateDnsZone -ResourceGroupName $rgName -Name 'privatelink.blob.core.windows.net' -ErrorAction SilentlyContinue
if (-not $privateDnsZone) {
    Write-Error "Private DNS Zone not found"
    exit 1
}

$vnetSpoke2 = Get-AzVirtualNetwork -ResourceGroupName $rgName -Name 'dnsmig-spoke2-vnet'
$existingLink = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $rgName -ZoneName 'privatelink.blob.core.windows.net' -Name "$Prefix-spoke2-link" -ErrorAction SilentlyContinue

if ($existingLink) {
    Write-Host "  ! Spoke2 VNet already linked"
} else {
    New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $rgName -ZoneName 'privatelink.blob.core.windows.net' -Name "$Prefix-spoke2-link" -VirtualNetworkId $vnetSpoke2.Id | Out-Null
    Write-Host "  ✓ Spoke2 VNet linked to Private DNS zone"
}

Write-Host "\nSwitching Spoke2 VNet to Azure-provided DNS..."
$vnetSpoke2.DhcpOptions.DnsServers = @()
Set-AzVirtualNetwork -VirtualNetwork $vnetSpoke2 | Out-Null
Write-Host "  ✓ Spoke2 VNet DNS servers cleared"

Write-Host ""
Write-Host "=================================================="
Write-Host "✓ Phase 5 Complete: Spoke2 Migrated"
Write-Host "=================================================="
Write-Host ""
Write-Host "Both Spoke1 and Spoke2 are now using Azure-provided DNS"
Write-Host "and resolving privatelink.blob.core.windows.net via Private DNS."
Write-Host ""
Write-Host "Next: Validate final DNS resolution with './scripts/validate.ps1 -Phase AfterSpoke2'"
