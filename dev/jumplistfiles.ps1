$auto = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
$cust = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations'
foreach ($d in @($auto, $cust)) {
  Write-Output ("=== " + $d)
  if (Test-Path $d) {
    Get-ChildItem $d -File | Sort-Object LastWriteTime -Descending | Select-Object -First 25 |
      ForEach-Object { Write-Output ("  {0,-40} {1,8} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime) }
    Write-Output ("  total files: " + (Get-ChildItem $d -File).Count)
  } else { Write-Output '  (missing)' }
}
