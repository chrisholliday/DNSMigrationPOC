param(
  [string]$Prefix = 'dnsmig',
  [string]$InboundResolverIp,
  [string]$OutputsPath
)

$root = Split-Path -Parent $PSScriptRoot
$defaultOutputs = Join-Path $root 'outputs\private-dns.json'
$resolvedOutputs = if ($OutputsPath) { $OutputsPath } else { $defaultOutputs }

if (-not $InboundResolverIp) {
  if (-not (Test-Path $resolvedOutputs)) {
    throw "Inbound resolver IP not provided and outputs file not found at $resolvedOutputs"
  }
  $json = Get-Content -Path $resolvedOutputs -Raw | ConvertFrom-Json
  $InboundResolverIp = $json.inboundResolverIp.value
}

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"
$onpremDnsVm = "$Prefix-onprem-vm-dns"
$hubDnsVm = "$Prefix-hub-vm-dns"

$updateScript = @"
set -e
sudo sed -i '/privatelink.blob./d' /etc/dnsmasq.d/custom.conf
echo "server=/privatelink.blob.core.windows.net/$InboundResolverIp" | sudo tee /etc/dnsmasq.d/privatelink-forward.conf >/dev/null
sudo systemctl restart dnsmasq
"@

Write-Host "Updating hub DNS forwarder to use inbound resolver: $InboundResolverIp"
Invoke-AzVMRunCommand -ResourceGroupName $rgHub -Name $hubDnsVm -CommandId 'RunShellScript' -ScriptString $updateScript | Out-Null

Write-Host "Updating on-prem DNS forwarder to use inbound resolver: $InboundResolverIp"
Invoke-AzVMRunCommand -ResourceGroupName $rgOnprem -Name $onpremDnsVm -CommandId 'RunShellScript' -ScriptString $updateScript | Out-Null

Write-Host "Forwarders updated."
