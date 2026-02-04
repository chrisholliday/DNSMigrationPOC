param(
  [string]$Prefix = 'dnsmig',
  [ValidateSet('Legacy','AfterPrivateDns','AfterForwarders','AfterSpoke1','AfterSpoke2')][string]$Phase = 'AfterSpoke2',
  [string]$OutputsPath
)

$root = Split-Path -Parent $PSScriptRoot
$defaultOutputs = Join-Path $root 'outputs\private-dns.json'
$resolvedOutputs = if ($OutputsPath) { $OutputsPath } else { $defaultOutputs }

$storage1 = $null
$storage2 = $null
if (Test-Path $resolvedOutputs) {
  $json = Get-Content -Path $resolvedOutputs -Raw | ConvertFrom-Json
  $storage1 = $json.spoke1StorageAccount.value
  $storage2 = $json.spoke2StorageAccount.value
}

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"
$rgSpoke1 = "$Prefix-rg-spoke1"
$rgSpoke2 = "$Prefix-rg-spoke2"

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
  Write-Host "--- $VmName ($ResourceGroup) ---"
  Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VmName -CommandId 'RunShellScript' -ScriptString $Script | Out-Null
}

Write-Host "Validation phase: $Phase"

$basicOnpremDns = "nslookup onprem-vm-client.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1"
$basicHubDns = "nslookup onprem-vm-dns.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1"
$basicSpoke = "nslookup onprem-vm-client.onprem.pvt; nslookup spoke1-vm-app.azure.pvt"

Invoke-RunCmd -ResourceGroup $rgOnprem -VmName $onpremDnsVm -Script $basicOnpremDns
Invoke-RunCmd -ResourceGroup $rgHub -VmName $hubDnsVm -Script $basicHubDns
Invoke-RunCmd -ResourceGroup $rgSpoke1 -VmName $spoke1Vm -Script $basicSpoke
Invoke-RunCmd -ResourceGroup $rgSpoke2 -VmName $spoke2Vm -Script $basicSpoke

if ($Phase -in @('AfterPrivateDns','AfterForwarders','AfterSpoke1','AfterSpoke2')) {
  if ($storage1) {
    Write-Host "Checking Private DNS zone records in hub RG..."
    Get-AzPrivateDnsRecordSet -ZoneName 'privatelink.blob.core.windows.net' -ResourceGroupName $rgHub -RecordType A | Select-Object -First 5 | Format-Table
  } else {
    Write-Host "Storage account outputs not found. Skipping Private DNS record validation."
  }
}

if ($Phase -in @('AfterForwarders','AfterSpoke1','AfterSpoke2') -and $storage1) {
  $storageTest1 = "nslookup $storage1.blob.core.windows.net"
  Invoke-RunCmd -ResourceGroup $rgSpoke1 -VmName $spoke1Vm -Script $storageTest1
  Invoke-RunCmd -ResourceGroup $rgOnprem -VmName $onpremClientVm -Script $storageTest1
}

if ($Phase -in @('AfterSpoke2') -and $storage2) {
  $storageTest2 = "nslookup $storage2.blob.core.windows.net"
  Invoke-RunCmd -ResourceGroup $rgSpoke2 -VmName $spoke2Vm -Script $storageTest2
}
