param(
  [string]$Location = 'centralus',
  [string]$Prefix = 'dnsmig'
)

$deployPrivateDns = Join-Path $PSScriptRoot '02-deploy-private-dns.ps1'

& $deployPrivateDns -Location $Location -Prefix $Prefix -LinkSpoke2

$rgSpoke2 = "$Prefix-rg-spoke2"
$vnetName = "$Prefix-spoke2-vnet"

$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgSpoke2
$vnet.DhcpOptions.DnsServers = @()
Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null

Write-Host "Spoke2 VNet linked to Private DNS and set to Azure-provided DNS."
