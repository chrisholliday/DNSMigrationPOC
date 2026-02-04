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
  Write-Host "Removing resource group: $rgName"
  Write-Host "This includes all VNets, VMs, Private DNS, and DNS Resolver resources..."
  Write-Host ""
  
  if ($Force) {
    Remove-AzResourceGroup -Name $rgName -Force -AsJob | Out-Null
    Write-Host "✓ Resource group deletion initiated (background job)"
  } else {
    Remove-AzResourceGroup -Name $rgName
    Write-Host "✓ Resource group removed"
  }
} else {
  Write-Host "⚠ Resource group '$rgName' not found"
}

Write-Host ""
Write-Host "Teardown complete"
