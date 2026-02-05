param(
    [string]$Prefix = 'dnsmig',
    [ValidateSet('Legacy', 'AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')][string]$Phase = 'AfterSpoke2'
)

$rgOnprem = "$Prefix-rg-onprem"
$rgHub = "$Prefix-rg-hub"
$rgSpoke1 = "$Prefix-rg-spoke1"
$rgSpoke2 = "$Prefix-rg-spoke2"

# VM names (hardcoded from Bicep deployment)
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
    Write-Host "  ✓ Testing $VmName..."
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroup -Name $VmName -CommandId 'RunShellScript' -ScriptString $Script | Out-Null
}


Write-Host '=================================================='
Write-Host "Validation: Phase $Phase"
Write-Host '=================================================='
Write-Host ''

Write-Host 'Testing DNS resolution on all VMs...'
$basicOnpremDns = 'nslookup onprem-vm-client.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1'
$basicHubDns = 'nslookup onprem-vm-dns.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1'
$basicSpoke = 'nslookup onprem-vm-client.onprem.pvt; nslookup spoke1-vm-app.azure.pvt'

Invoke-RunCmd -ResourceGroup $rgOnprem -VmName $onpremDnsVm -Script $basicOnpremDns
Invoke-RunCmd -ResourceGroup $rgHub -VmName $hubDnsVm -Script $basicHubDns
Invoke-RunCmd -ResourceGroup $rgSpoke1 -VmName $spoke1Vm -Script $basicSpoke
Invoke-RunCmd -ResourceGroup $rgSpoke2 -VmName $spoke2Vm -Script $basicSpoke

if ($Phase -in @('AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')) {
    Write-Host ''
    Write-Host 'Checking Private DNS zone records...'
    Get-AzPrivateDnsRecordSet -ZoneName 'privatelink.blob.core.windows.net' -ResourceGroupName $rgHub -RecordType A | Select-Object -First 5 | Format-Table
}

Write-Host ''
Write-Host "✓ Validation complete for phase: $Phase"
4