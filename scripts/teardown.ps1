param(
  [string]$Prefix = 'dnsmig',
  [switch]$Force
)

$rgNames = @(
  "$Prefix-rg-onprem",
  "$Prefix-rg-hub",
  "$Prefix-rg-spoke1",
  "$Prefix-rg-spoke2"
)

foreach ($rg in $rgNames) {
  if (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
    Write-Host "Removing $rg..."
    if ($Force) {
      Remove-AzResourceGroup -Name $rg -Force -AsJob | Out-Null
    } else {
      Remove-AzResourceGroup -Name $rg
    }
  }
}
