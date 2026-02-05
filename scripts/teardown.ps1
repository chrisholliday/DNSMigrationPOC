param(
  [string]$Prefix = 'dnsmig',
  [switch]$Force
)

Write-Host "=================================================="
Write-Host "Teardown: DNS Migration POC"
Write-Host "=================================================="
Write-Host ""

$rgName = "$Prefix-rg"

if (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue) {
  if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to delete resource group '$rgName'"
    if ($confirm -ne 'yes') {
      Write-Host "Teardown cancelled"
      return
    }
  }

  Write-Host "Removing resource group: $rgName"
  Write-Host "This includes all VNets, VMs, Private DNS, and DNS Resolver resources..."
  Write-Host ""

  $job = Remove-AzResourceGroup -Name $rgName -Force -Confirm:$false -AsJob
  Write-Host "✓ Resource group deletion initiated (background job)"

  while ($true) {
    $current = Get-Job -Id $job.Id -ErrorAction SilentlyContinue
    if (-not $current) {
      Write-Host "✓ Deletion job finished"
      break
    }

    if ($current.State -in @('Completed','Failed','Stopped')) {
      Write-Host "✓ Deletion job state: $($current.State)"
      break
    }

    Write-Host "... deletion in progress"
    Start-Sleep -Seconds 15
  }
} else {
  Write-Host "⚠ Resource group '$rgName' not found"
}

Write-Host ""
Write-Host "Teardown complete"
