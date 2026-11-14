$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'no dock process' } else {
  $p | ForEach-Object { Write-Output ("pid=" + $_.Id + " path=" + $_.Path + " start=" + $_.StartTime) }
}
$h = Get-Process | Where-Object { $_.ProcessName -like '*dock*' } | Select-Object -First 5
Write-Output ("count=" + (@($p).Count))
