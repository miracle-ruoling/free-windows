param([string]$Out = 'menu_blank', [int]$ClickY = 0)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
$strip = [S]::ByClass('DockStripWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($strip, [ref]$r)
$x = $r.Left + 4
$y = $r.Top + [int](($r.Bottom - $r.Top) / 2)
Write-Output ("strip $($r.Left),$($r.Top) right-click blank at $x,$y")
[S]::MoveTo($x, $y)
Start-Sleep -Milliseconds 400
[S]::RightClick()
Start-Sleep -Milliseconds 700
$menu = [S]::ByClass('#32768')
if ($menu -eq [IntPtr]::Zero) { Write-Output 'no menu'; exit 1 }
$mr = New-Object S+RECT
[void][S]::GetWindowRect($menu, [ref]$mr)
Write-Output ("menu at {0},{1} {2}x{3}" -f $mr.Left, $mr.Top, ($mr.Right - $mr.Left), ($mr.Bottom - $mr.Top))
Shot ($Out + '.png')
if ($ClickY -gt 0) {
  [S]::MoveTo(($mr.Left + 60), ($mr.Top + $ClickY))
  Start-Sleep -Milliseconds 200
  [S]::LeftClick()
  Start-Sleep -Milliseconds 1200
  Write-Output ("clicked item at +$ClickY")
}
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 8))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|rescan|menu:' } | ForEach-Object { Write-Output ("LOG " + $_) }
