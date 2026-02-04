param(
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig',
    [switch]$LinkSpoke2
)

$root = Split-Path -Parent $PSScriptRoot
$bicepFile = Join-Path $root 'bicep\private-dns.bicep'
$outputDir = Join-Path $root 'outputs'
$outputFile = Join-Path $outputDir 'private-dns.json'

$rgNames = @{
    hub    = "$Prefix-rg-hub"
    spoke1 = "$Prefix-rg-spoke1"
    spoke2 = "$Prefix-rg-spoke2"
}

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Write-Host 'Deploying Azure Private DNS and Private Resolver...'
$deployment = New-AzSubscriptionDeployment \
-Name "$Prefix-private-dns" \
-Location $Location \
-TemplateFile $bicepFile \
-TemplateParameterObject @{
    location   = $Location
    prefix     = $Prefix
    rgNames    = $rgNames
    linkSpoke2 = [bool]$LinkSpoke2
}

$outputs = $deployment.Outputs
$outputs | ConvertTo-Json -Depth 6 | Set-Content -Path $outputFile

Write-Host "Saved outputs to $outputFile"
$outputs | ConvertTo-Json -Depth 6 | Write-Host
