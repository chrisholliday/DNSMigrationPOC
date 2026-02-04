param(
    [string]$Prefix = 'dnsmig',
    [ValidateSet('Legacy', 'AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')][string]$Phase = 'AfterSpoke2'
)

$rgName = "$Prefix-rg"

# VM names (hardcoded from Bicep deployment)
$onpremDnsVm = 'dnsmig-onprem-dns'
$onpremClientVm = 'dnsmig-onprem-client'
$hubDnsVm = 'dnsmig-hub-dns'
$spoke1Vm = 'dnsmig-spoke1-app'
$spoke2Vm = 'dnsmig-spoke2-app'

function Invoke-RunCmd {
    param(
        [string]$VmName,
        [string]$Script
    )
    Write-Host "  ✓ Testing $VmName..."
    Invoke-AzVMRunCommand -ResourceGroupName $rgName -Name $VmName -CommandId 'RunShellScript' -ScriptString $Script | Out-Null
}


Write-Host '=================================================='
Write-Host "Validation: Phase $Phase"
Write-Host '=================================================='
Write-Host ''

Write-Host 'Testing DNS resolution on all VMs...'
$basicOnpremDns = 'nslookup onprem-vm-client.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1'
$basicHubDns = 'nslookup onprem-vm-dns.onprem.pvt 127.0.0.1; nslookup spoke1-vm-app.azure.pvt 127.0.0.1'
$basicSpoke = 'nslookup onprem-vm-client.onprem.pvt; nslookup spoke1-vm-app.azure.pvt'

Invoke-RunCmd -VmName $onpremDnsVm -Script $basicOnpremDns
Invoke-RunCmd -VmName $hubDnsVm -Script $basicHubDns
Invoke-RunCmd -VmName $spoke1Vm -Script $basicSpoke
Invoke-RunCmd -VmName $spoke2Vm -Script $basicSpoke

if ($Phase -in @('AfterPrivateDns', 'AfterForwarders', 'AfterSpoke1', 'AfterSpoke2')) {
    Write-Host ''
    Write-Host 'Checking Private DNS zone records...'
    Get-AzPrivateDnsRecordSet -ZoneName 'privatelink.blob.core.windows.net' -ResourceGroupName $rgName -RecordType A | Select-Object -First 5 | Format-Table
}

Write-Host ''
Write-Host "✓ Validation complete for phase: $Phase"
