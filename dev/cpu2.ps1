param([int]$X = 0, [int]$Y = 1000)
Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'
$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'dock not running'; exit }
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 1200
$t0 = $p.TotalProcessorTime.TotalMilliseconds
Start-Sleep -Seconds 10
$p.Refresh()
$t1 = $p.TotalProcessorTime.TotalMilliseconds
Write-Output ("cursor at " + $X + "," + $Y + " -> cpu ms over 10s: " + [int]($t1 - $t0))
