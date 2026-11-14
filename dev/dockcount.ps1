$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'no dock process' } else {
  $p | ForEach-Object { Write-Output ("dock pid=" + $_.Id + " start=" + $_.StartTime + " path=" + $_.Path) }
}
$q = Get-Process | Where-Object { $_.ProcessName -eq 'dock' }
Write-Output ("count=" + (@($q).Count))
