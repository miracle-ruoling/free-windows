param([string]$Exe = 'qq.exe', [int]$ItemY = -1, [string]$Out = 't_slotpick', [switch]$NoClick)
# Closed-loop strip click: move the pointer, read the dock's own "hover -> N" log line to
# find out which slot is really under it, and correct. The strip's layout shifts when
# windows come and go, so computing the x from a stale item list is unreliable.
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function LastHover() {
  $lines = Get-LogLines
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $m = [regex]::Match($lines[$i], '\d{2}:\d{2}:\d{2}\.\d{3}\s+hover -> (-?\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
  }
  return -99
}
function ItemsFromLog() {
  $lines = Get-LogLines
  $idx = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '\d{2}:\d{2}:\d{2}\.\d{3} items=(\d+)') { $idx = $i; break } }
  if ($idx -lt 0) { return @() }
  $n = [int]([regex]::Match($lines[$idx], 'items=(\d+)').Groups[1].Value)
  $out = @()
  for ($i = $idx + 1; $i -lt [Math]::Min($idx + 1 + $n, $lines.Count); $i++) {
    $m = [regex]::Match($lines[$i], '\[(\d+)\] hwnd=([0-9A-Fa-f]+) pin=(\d) exe=(.*?) title=(.*)$')
    if ($m.Success) { $out += [pscustomobject]@{ idx=[int]$m.Groups[1].Value; hwnd=$m.Groups[2].Value; pin=$m.Groups[3].Value; exe=$m.Groups[4].Value; title=$m.Groups[5].Value } } else { break }
  }
  return $out
}
$items = ItemsFromLog
if ($items.Count -eq 0) { Write-Output 'no item list'; exit 1 }
$target = -1
for ($i = 0; $i -lt $items.Count; $i++) { if ($items[$i].exe.ToLower().Contains($Exe.ToLower())) { $target = $i; break } }
if ($target -lt 0) { Write-Output ('no slot for ' + $Exe); exit 2 }
Write-Output ("target slot $target [" + $items[$target].idx + "] " + $items[$target].exe + " | " + $items[$target].title)

$strip = [S]::ByClass('DockStripWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($strip, [ref]$r)
$H = $r.Bottom - $r.Top
$y = $r.Top + [int]($H / 2)
$pad = 10; $gap = 6
$icon = [Math]::Min($H - 2 * $pad, 72); if ($icon -lt 18) { $icon = 18 }
$cell = $icon + $gap
$W = $r.Right - $r.Left
$cap = [int](($W - 2 * $pad + $gap) / $cell)
$show = if ($cap -gt 1) { $cap - 1 } else { $cap }
$visible = [Math]::Min($items.Count, $show)
$total = $visible * $cell
if ($cap -gt 1) { $total += $icon + $gap }
$total -= $gap
$start = $pad + [int](($W - 2 * $pad - $total) / 2)
$x = $r.Left + $start + $target * $cell + [int]($icon / 2)
for ($try = 0; $try -lt 6; $try++) {
  [S]::MoveTo($x, $y)
  Start-Sleep -Milliseconds 260
  $h = LastHover
  Write-Output ("  try $try x=$x hover=$h")
  if ($h -eq $target) { break }
  if ($h -lt -50) { break }
  $x += ($target - $h) * $cell
}
if ((LastHover) -ne $target) { Write-Output 'could not land on the slot'; exit 3 }
[S]::RightClick()
Start-Sleep -Milliseconds 800
$menu = [S]::ByClass('#32768')
if ($menu -eq [IntPtr]::Zero) { Write-Output 'no menu'; exit 4 }
$mr = New-Object S+RECT
[void][S]::GetWindowRect($menu, [ref]$mr)
Write-Output ("menu {0},{1} {2}x{3}" -f $mr.Left,$mr.Top,($mr.Right-$mr.Left),($mr.Bottom-$mr.Top))
Shot ($Out + '_menu.png')
if ($NoClick -or $ItemY -lt 0) {
  [S]::MoveTo(1600, 950); Start-Sleep -Milliseconds 150; [S]::LeftClick(); Start-Sleep -Milliseconds 200
  Write-Output 'menu closed'
} else {
  [S]::MoveTo(($mr.Left + 70), ($mr.Top + $ItemY))
  Start-Sleep -Milliseconds 200
  [S]::LeftClick()
  Start-Sleep -Milliseconds 1500
}
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 12))..($lines.Count - 1)] | Where-Object { $_ -match 'menu:|launch|activate|minimize' } | ForEach-Object { Write-Output ("LOG " + $_) }
