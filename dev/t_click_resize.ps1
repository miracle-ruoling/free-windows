# §3.40: the border band is armed, not started. Two checks:
#   * a press on the band that travels really resizes (the gesture still exists)
#   * the same press without travel does not resize (it becomes a click - see t_click_hit.ps1)
# Restores the strip's size and the cursor at the end.
param([int]$Travel = 24)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

$strip = [S]::ByClass('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no DockStripWindow'; exit 1 }
if (-not (Wait-Idle 1200 30)) { Write-Output 'user busy'; exit 1 }

function Rect { $r = New-Object S+RECT; [void][S]::GetWindowRect($strip, [ref]$r); return $r }
function Client { $c = New-Object S+RECT; [void][S]::GetClientRect($strip, [ref]$c); return $c }
function CursorTo([int]$x, [int]$y) { [void][S]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 60 }
function Msg([uint32]$m, [int]$x, [int]$y) {
  $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
  [void][S]::SendMessage($strip, $m, [IntPtr]1, $lp)
}

$start = New-Object S+POINT
[void][S]::GetCursorPos([ref]$start)
# 贴边隐藏: the strip parks off-screen and only wakes when the pointer goes to its edge.
$r0 = Rect
if ($r0.Top -lt 0 -or $r0.Bottom -le 24) {
  CursorTo ([int](($r0.Left + $r0.Right) / 2)) 2
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 100
    $r0 = Rect
    if ($r0.Top -ge 0 -and $r0.Bottom -gt 24) { break }
  }
  Start-Sleep -Milliseconds 500          # let the wake slide finish
  $r0 = Rect
  Write-Output ("woke the strip: {0},{1} {2}x{3}" -f $r0.Left, $r0.Top, ($r0.Right - $r0.Left), ($r0.Bottom - $r0.Top))
}
$c0 = Client
Write-Output ("start: screen {0},{1} {2}x{3}  client {4}x{5}" -f $r0.Left, $r0.Top, ($r0.Right - $r0.Left), ($r0.Bottom - $r0.Top), $c0.Right, $c0.Bottom)

# drag the bottom edge down by $Travel and back
for ($pass = 1; $pass -le 2; $pass++) {
  $dx = if ($pass -eq 1) { $Travel } else { -$Travel }
  $c = Client
  $x = $r0.Left + [int]($c.Right / 2)
  $y = $r0.Top + $c.Bottom - 5
  $before = (Get-LogLines).Count
  CursorTo $x $y
  Msg 0x0201 $([int]($c.Right / 2)) ($c.Bottom - 5)
  CursorTo $x ($y + $dx)
  Msg 0x0200 $([int]($c.Right / 2)) ($c.Bottom - 5 + $dx)
  Msg 0x0200 $([int]($c.Right / 2)) ($c.Bottom - 5 + $dx)
  Start-Sleep -Milliseconds 120
  Msg 0x0202 $([int]($c.Right / 2)) ($c.Bottom - 5 + $dx)
  Start-Sleep -Milliseconds 350
  $r = Rect
  $newH = $r.Bottom - $r.Top
  $armed = @(Get-LogLines | Select-Object -Skip $before | Select-String 'resize: armed|resize: press at the edge' | ForEach-Object { $_.Line })
  Write-Output ("pass {0} (travel {1}): height {2} -> {3}  log: {4}" -f $pass, $dx, ($r0.Bottom - $r0.Top), $newH, ($armed -join ' | '))
}
[void][S]::SetCursorPos($start.X, $start.Y)
$r1 = Rect
Write-Output ("end: screen {0},{1} {2}x{3}  (restored: {4})" -f $r1.Left, $r1.Top, ($r1.Right - $r1.Left), ($r1.Bottom - $r1.Top),
  (($r1.Left -eq $r0.Left) -and ($r1.Top -eq $r0.Top) -and ($r1.Right -eq $r0.Right) -and ($r1.Bottom -eq $r0.Bottom)))
