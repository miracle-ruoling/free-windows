$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'dock not running'; exit }
$t0 = $p.TotalProcessorTime.TotalMilliseconds
Start-Sleep -Seconds 10
$p.Refresh()
$t1 = $p.TotalProcessorTime.TotalMilliseconds
Write-Output ("cpu ms over 10s: " + [int]($t1 - $t0) + "  (~" + [int](($t1 - $t0) / 100) + "% of one core)")
Write-Output ("working set MB: " + [int]($p.WorkingSet64 / 1MB))
