param(
    [string]$Location = 'centralus',
    [string]$Prefix = 'dnsmig'
)

$root = Split-Path -Parent $PSScriptRoot
$bicepFile = Join-Path $root 'bicep\private-dns.bicep'
$rgHub = "$Prefix-rg-hub"
$rgSpoke1 = "$Prefix-rg-spoke1"
$rgSpoke2 = "$Prefix-rg-spoke2"

Write-Host '=================================================='
Write-Host 'Phase 2: Deploy Azure Private DNS'
Write-Host '=================================================='

Write-Host 'Deploying Azure Private DNS zone and resolver...'
$deployParams = @{
    Location                = $Location
    TemplateFile            = $bicepFile
    TemplateParameterObject = @{
        location = $Location
        prefix   = $Prefix
        rgNames  = @{
            hub    = $rgHub
            spoke1 = $rgSpoke1
            spoke2 = $rgSpoke2
        }
    }
}

$deployment = New-AzDeployment @deployParams

if ($deployment.ProvisioningState -eq 'Succeeded') {
    Write-Host '✓ Phase 2 Complete: Azure Private DNS deployed'
    Write-Host ''
    Write-Host 'Deployed resources:'
    Write-Host '  - Private DNS Zone: privatelink.blob.core.windows.net'
    Write-Host "  - DNS Resolver: $Prefix-dns-resolver"
    Write-Host "  - Inbound Endpoint: $Prefix-resolver-inbound"
    Write-Host "  - Outbound Endpoint: $Prefix-resolver-outbound"
}
else {
    Write-Error "Phase 2 deployment failed: $($deployment.ProvisioningState)"
    exit 1
}

Write-Host ''
Write-Host "Next: Configure legacy DNS forwarders with './scripts/04-configure-legacy-forwarders.ps1'"
