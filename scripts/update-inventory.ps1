#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates the DEPLOYMENT-INVENTORY.md file with actual deployed resource information.

.DESCRIPTION
    Queries Azure for deployed resources and populates the inventory document with:
    - Storage account names and private endpoint IPs
    - VM names and IP addresses
    - DNS Private Resolver information (if deployed)
    - Deployment timestamps

.EXAMPLE
    ./scripts/update-inventory.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Continue'

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host 'Updating Deployment Inventory' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

$inventoryFile = Join-Path $PSScriptRoot '..' 'DEPLOYMENT-INVENTORY.md'

# Check if file exists
if (-not (Test-Path $inventoryFile)) {
    Write-Host 'ERROR: DEPLOYMENT-INVENTORY.md not found!' -ForegroundColor Red
    exit 1
}

# Read current inventory
$content = Get-Content $inventoryFile -Raw

Write-Host 'Gathering resource information...' -ForegroundColor Yellow
Write-Host ''

# ============================================================================
# Query Resource Groups
# ============================================================================
Write-Host '[1/5] Checking resource groups...' -ForegroundColor Cyan
$rgs = @{
    'onprem' = 'rg-onprem-dnsmig'
    'hub'    = 'rg-hub-dnsmig'
    'spoke1' = 'rg-spoke1-dnsmig'
    'spoke2' = 'rg-spoke2-dnsmig'
}

$rgInfo = @{}
foreach ($key in $rgs.Keys) {
    $rgName = $rgs[$key]
    $rgDetails = az group show -n $rgName --query '{location:location}' -o json 2>$null | ConvertFrom-Json
    if ($rgDetails) {
        $rgInfo[$key] = @{
            Name     = $rgName
            Location = $rgDetails.location
            Exists   = $true
        }
        Write-Host "  ✓ $rgName ($($rgDetails.location))" -ForegroundColor Green
    }
    else {
        $rgInfo[$key] = @{
            Name     = $rgName
            Location = 'N/A'
            Exists   = $false
        }
        Write-Host "  ✗ $rgName (not found)" -ForegroundColor Yellow
    }
}

# ============================================================================
# Query Storage Accounts
# ============================================================================
Write-Host "`n[2/5] Querying storage accounts..." -ForegroundColor Cyan
$storageInfo = @{}

foreach ($spoke in @('spoke1', 'spoke2')) {
    $rgName = $rgs[$spoke]
    if ($rgInfo[$spoke].Exists) {
        $storageAccounts = az storage account list -g $rgName --query '[].{name:name, id:id}' -o json 2>$null | ConvertFrom-Json
        
        if ($storageAccounts -and $storageAccounts.Count -gt 0) {
            $sa = $storageAccounts[0]
            
            # Get private endpoint details
            $peList = az network private-endpoint list -g $rgName --query "[?privateLinkServiceConnections[0].privateLinkServiceId=='$($sa.id)'].{name:name, id:id}" -o json 2>$null | ConvertFrom-Json
            
            $peIP = 'N/A'
            if ($peList -and $peList.Count -gt 0) {
                $pe = $peList[0]
                $peDetails = az network private-endpoint show --ids $pe.id --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv 2>$null
                if ($peDetails) {
                    $peIP = $peDetails
                }
            }
            
            $storageInfo[$spoke] = @{
                Name            = $sa.name
                PublicFQDN      = "$($sa.name).blob.core.windows.net"
                PrivatelinkFQDN = "$($sa.name).privatelink.blob.core.windows.net"
                PrivateIP       = $peIP
            }
            
            Write-Host "  ✓ $spoke`: $($sa.name) (PE IP: $peIP)" -ForegroundColor Green
        }
        else {
            $storageInfo[$spoke] = @{
                Name            = '*Not yet deployed*'
                PublicFQDN      = '.blob.core.windows.net'
                PrivatelinkFQDN = '.privatelink.blob.core.windows.net'
                PrivateIP       = '-'
            }
            Write-Host "  ✗ $spoke`: No storage accounts found" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# Query VMs and IPs
# ============================================================================
Write-Host "`n[3/5] Querying VMs and IP addresses..." -ForegroundColor Cyan
$vmInfo = @{}

foreach ($key in $rgs.Keys) {
    $rgName = $rgs[$key]
    if ($rgInfo[$key].Exists) {
        $vms = az vm list -g $rgName --show-details --query '[].{name:name, privateIps:privateIps, powerState:powerState}' -o json 2>$null | ConvertFrom-Json
        
        if ($vms) {
            $vmInfo[$key] = $vms
            foreach ($vm in $vms) {
                $status = if ($vm.powerState -eq 'VM running') { '✓' } else { '○' }
                Write-Host "  $status $($vm.name) - $($vm.privateIps) ($($vm.powerState))" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  ✗ $key`: No VMs found" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# Query DNS Private Resolver (if exists)
# ============================================================================
Write-Host "`n[4/5] Checking for DNS Private Resolver..." -ForegroundColor Cyan
$dnsResolverInfo = $null

if ($rgInfo['hub'].Exists) {
    try {
        # Set a timeout for the command - use Start-Job to prevent hanging
        $resolverJob = Start-Job -ScriptBlock {
            param($rgName)
            az dns-resolver list -g $rgName --query '[0].{name:name, id:id}' -o json 2>&1
        } -ArgumentList $rgs['hub']
        
        # Wait max 10 seconds
        $completed = Wait-Job -Job $resolverJob -Timeout 10
        
        if ($completed) {
            $resolverOutput = Receive-Job -Job $resolverJob
            Remove-Job -Job $resolverJob -Force
            
            if ($resolverOutput -and $resolverOutput -notlike '*ERROR*' -and $resolverOutput -notlike '*command not found*') {
                $resolver = $resolverOutput | ConvertFrom-Json
                
                if ($resolver -and $resolver.name) {
                    $inboundEPs = az dns-resolver inbound-endpoint list -g $rgs['hub'] --dns-resolver-name $resolver.name --query '[].{name:name, ip:ipConfigurations[0].privateIpAddress}' -o json 2>$null | ConvertFrom-Json
                    $outboundEPs = az dns-resolver outbound-endpoint list -g $rgs['hub'] --dns-resolver-name $resolver.name --query '[].{name:name}' -o json 2>$null | ConvertFrom-Json
                    
                    $dnsResolverInfo = @{
                        Name             = $resolver.name
                        InboundEndpoint  = if ($inboundEPs) { $inboundEPs[0].name } else { 'N/A' }
                        InboundIP        = if ($inboundEPs) { $inboundEPs[0].ip } else { 'N/A' }
                        OutboundEndpoint = if ($outboundEPs) { $outboundEPs[0].name } else { 'N/A' }
                    }
                    
                    Write-Host "  ✓ DNS Private Resolver: $($resolver.name)" -ForegroundColor Green
                    Write-Host "    - Inbound EP: $($dnsResolverInfo.InboundEndpoint) ($($dnsResolverInfo.InboundIP))" -ForegroundColor Green
                    Write-Host "    - Outbound EP: $($dnsResolverInfo.OutboundEndpoint)" -ForegroundColor Green
                }
                else {
                    Write-Host '  ○ DNS Private Resolver not yet deployed' -ForegroundColor Yellow
                }
            }
            else {
                Write-Host '  ○ DNS Private Resolver feature not available (Phase 8+)' -ForegroundColor Yellow
            }
        }
        else {
            # Timeout occurred
            Remove-Job -Job $resolverJob -Force
            Write-Host '  ○ DNS Private Resolver query timed out (not deployed)' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ○ Unable to query DNS Private Resolver: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================================
# Update Inventory File
# ============================================================================
Write-Host "`n[5/5] Updating inventory file..." -ForegroundColor Cyan

# Update Resource Groups table
if ($rgInfo['onprem'].Exists) {
    $content = $content -replace '\| On-Premises \| rg-onprem-dnsmig \| - \|', "| On-Premises | rg-onprem-dnsmig | $($rgInfo['onprem'].Location) |"
}
if ($rgInfo['hub'].Exists) {
    $content = $content -replace '\| Hub \| rg-hub-dnsmig \| - \|', "| Hub | rg-hub-dnsmig | $($rgInfo['hub'].Location) |"
}
if ($rgInfo['spoke1'].Exists) {
    $content = $content -replace '\| Spoke 1 \| rg-spoke1-dnsmig \| - \|', "| Spoke 1 | rg-spoke1-dnsmig | $($rgInfo['spoke1'].Location) |"
}
if ($rgInfo['spoke2'].Exists) {
    $content = $content -replace '\| Spoke 2 \| rg-spoke2-dnsmig \| - \|', "| Spoke 2 | rg-spoke2-dnsmig | $($rgInfo['spoke2'].Location) |"
}

# Update Storage Accounts table
if ($storageInfo['spoke1']) {
    $spoke1Row = "| Spoke 1 | $($storageInfo['spoke1'].Name) | $($storageInfo['spoke1'].PublicFQDN) | $($storageInfo['spoke1'].PrivateIP) | $($storageInfo['spoke1'].PrivatelinkFQDN) |"
    $content = $content -replace '\| Spoke 1 \| \*Not yet deployed\* \| \.blob\.core\.windows\.net \| - \| \.privatelink\.blob\.core\.windows\.net \|', $spoke1Row
}

if ($storageInfo['spoke2']) {
    $spoke2Row = "| Spoke 2 | $($storageInfo['spoke2'].Name) | $($storageInfo['spoke2'].PublicFQDN) | $($storageInfo['spoke2'].PrivateIP) | $($storageInfo['spoke2'].PrivatelinkFQDN) |"
    $content = $content -replace '\| Spoke 2 \| \*Not yet deployed\* \| \.blob\.core\.windows\.net \| - \| \.privatelink\.blob\.core\.windows\.net \|', $spoke2Row
}

# Update DNS Private Resolver table
if ($dnsResolverInfo) {
    $dprRow = "| DNS Private Resolver | $($dnsResolverInfo.Name) | $($dnsResolverInfo.InboundIP) | hub-vnet | Deployed |"
    $content = $content -replace '\| DNS Private Resolver \| \*Not yet deployed\* \| - \| hub-vnet \| Not deployed \|', $dprRow
    
    $inboundRow = "| Inbound Endpoint | $($dnsResolverInfo.InboundEndpoint) | $($dnsResolverInfo.InboundIP) | hub-vnet | Deployed |"
    $content = $content -replace '\| Inbound Endpoint \| \*Not yet deployed\* \| - \| hub-vnet \| Not deployed \|', $inboundRow
    
    $outboundRow = "| Outbound Endpoint | $($dnsResolverInfo.OutboundEndpoint) | - | hub-vnet | Deployed |"
    $content = $content -replace '\| Outbound Endpoint \| \*Not yet deployed\* \| - \| hub-vnet \| Not deployed \|', $outboundRow
}

# Update Last Updated timestamp
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$content = $content -replace '\*\*Date:\*\* \*Run update script to populate\*', "**Date:** $timestamp"
$content = $content -replace '\*\*Updated By:\*\* \*Automated deployment script\*', '**Updated By:** update-inventory.ps1'

# Write updated content
$content | Set-Content $inventoryFile -NoNewline

Write-Host "  ✓ Inventory file updated: $inventoryFile" -ForegroundColor Green

# ============================================================================
# Display Quick Reference
# ============================================================================
Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Quick Reference - Copy/Paste for Demos' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ''

if ($storageInfo['spoke1'].Name -ne '*Not yet deployed*') {
    Write-Host 'Storage Account Names:' -ForegroundColor Cyan
    Write-Host "  Spoke1: $($storageInfo['spoke1'].Name)" -ForegroundColor White
    Write-Host "  Spoke2: $($storageInfo['spoke2'].Name)" -ForegroundColor White
    Write-Host ''
    
    Write-Host 'PowerShell Variables:' -ForegroundColor Cyan
    Write-Host "  `$spoke1Storage = '$($storageInfo['spoke1'].Name)'" -ForegroundColor White
    Write-Host "  `$spoke2Storage = '$($storageInfo['spoke2'].Name)'" -ForegroundColor White
    Write-Host ''
    
    Write-Host 'DNS Resolution Test Commands:' -ForegroundColor Cyan
    Write-Host "  nslookup $($storageInfo['spoke1'].PublicFQDN)" -ForegroundColor White
    Write-Host "  nslookup $($storageInfo['spoke2'].PublicFQDN)" -ForegroundColor White
    Write-Host ''
}

Write-Host 'VM Test Loop:' -ForegroundColor Cyan
Write-Host '  $vms = @(''onprem-vm-web'', ''hub-vm-web'', ''spoke1-vm-web1'', ''spoke2-vm-web1'')' -ForegroundColor White
Write-Host '  foreach ($vm in $vms) {' -ForegroundColor White
Write-Host '      $rg = if ($vm -like ''onprem-*'') { ''rg-onprem-dnsmig'' } elseif ($vm -like ''spoke1-*'') { ''rg-spoke1-dnsmig'' } elseif ($vm -like ''spoke2-*'') { ''rg-spoke2-dnsmig'' } else { ''rg-hub-dnsmig'' }' -ForegroundColor White
Write-Host '      az vm run-command invoke --resource-group $rg --name $vm --command-id RunShellScript --scripts ''nslookup web.azure.pvt''' -ForegroundColor White
Write-Host '  }' -ForegroundColor White
Write-Host ''

Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host 'Inventory Update Complete!' -ForegroundColor Green
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Green
