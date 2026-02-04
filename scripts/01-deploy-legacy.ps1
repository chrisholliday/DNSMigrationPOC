param(
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig',
    [string]$AdminUsername = 'azureuser',
    [Parameter(Mandatory = $true)][string]$SshPublicKeyPath,
    [string]$VmSize = 'Standard_B1s'
)

$root = Split-Path -Parent $PSScriptRoot
$bicepFile = Join-Path $root 'bicep\legacy.bicep'

$sshPublicKey = Get-Content -Path $SshPublicKeyPath -Raw

$rgNames = @{
    onprem = "$Prefix-rg-onprem"
    hub    = "$Prefix-rg-hub"
    spoke1 = "$Prefix-rg-spoke1"
    spoke2 = "$Prefix-rg-spoke2"
}

Write-Host 'Creating resource groups...'
$rgNames.Values | ForEach-Object { New-AzResourceGroup -Name $_ -Location $Location -Force | Out-Null }

Write-Host 'Deploying legacy environment (Linux DNS only)...'
$deployment = New-AzSubscriptionDeployment \
-Name "$Prefix-legacy" \
-Location $Location \
-TemplateFile $bicepFile \
-TemplateParameterObject @{
    location      = $Location
    prefix        = $Prefix
    adminUsername = $AdminUsername
    sshPublicKey  = $sshPublicKey
    vmSize        = $VmSize
    rgNames       = $rgNames
}

$deployment | Select-Object -ExpandProperty Outputs | ConvertTo-Json -Depth 5 | Write-Host
