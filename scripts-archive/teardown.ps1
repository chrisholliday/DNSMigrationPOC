param(
  [string]$Prefix = 'dnsmig',
  [switch]$Force
)

Write-Host '=================================================='
Write-Host 'Teardown: DNS Migration POC'
Write-Host '=================================================='
Write-Host ''

$rgNames = @(
  "$Prefix-rg-onprem",
  "$Prefix-rg-hub",
  "$Prefix-rg-spoke1",
  "$Prefix-rg-spoke2"
)

# Check which resource groups exist
$existingRgs = @()
foreach ($rgName in $rgNames) {
  if (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue) {
    $existingRgs += $rgName
  }
}

if ($existingRgs.Count -eq 0) {
  Write-Host "⚠ No resource groups found with prefix '$Prefix'"
  Write-Host ''
  Write-Host 'Teardown complete'
  return
}

Write-Host "Found $($existingRgs.Count) resource group(s):"
foreach ($rg in $existingRgs) {
  Write-Host "  - $rg"
}
Write-Host ''

if (-not $Force) {
  $confirm = Read-Host "Type 'yes' to delete all resource groups"
  if ($confirm -ne 'yes') {
    Write-Host 'Teardown cancelled'
    return
  }
}

Write-Host 'Removing resource groups...'
Write-Host 'This includes all VNets, VMs, Private DNS, and DNS Resolver resources...'
Write-Host ''

$jobs = @()
foreach ($rgName in $existingRgs) {
  Write-Host "Initiating deletion of: $rgName"
  $job = Remove-AzResourceGroup -Name $rgName -Force -Confirm:$false -AsJob
  $jobs += @{ Name = $rgName; Job = $job }
}

Write-Host ''
Write-Host '✓ All resource group deletions initiated (background jobs)'
Write-Host ''

# Monitor deletion progress
$completed = 0
while ($completed -lt $jobs.Count) {
  $completed = 0
  foreach ($item in $jobs) {
    $current = Get-Job -Id $item.Job.Id -ErrorAction SilentlyContinue
    if (-not $current -or $current.State -in @('Completed', 'Failed', 'Stopped')) {
      $completed++
    }
  }
  
  if ($completed -lt $jobs.Count) {
    Write-Host "... deletion in progress ($completed/$($jobs.Count) completed)"
    Start-Sleep -Seconds 15
  }
}

Write-Host ''
Write-Host '✓ All deletion jobs completed'
Write-Host ''
Write-Host 'Teardown complete'
