param(
  [string]$Prefix = 'dnsmig'
)

$rgSpoke1 = "$Prefix-rg-spoke1"
$vnetName = "$Prefix-spoke1-vnet"

$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgSpoke1
$vnet.DhcpOptions.DnsServers = @()
Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null

Write-Host "Spoke1 VNet DNS set to Azure-provided DNS."
