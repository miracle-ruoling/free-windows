param([string]$Exe = 'explorer', [string]$Out = 't_stripclick')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function ItemsFromLog() {
  $lines = Get-LogLines
  $idx = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '\d{2}:\d{2}:\d{2}\.\d{3} items=(\d+)') { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $n = [int]([regex]::Match($lines[$idx], '\d{2}:\d{2}:\d{2}\.\d{3} items=(\d+)').Groups[1].Value)
  $out = @()
  for ($i = $idx + 1; $i -lt [Math]::Min($idx + 1 + $n, $lines.Count); $i++) {
    $m = [regex]::Match($lines[$i], '\[(\d+)\] hwnd=([0-9A-Fa-f]+) pin=(\d) exe=(.*?) title=(.*)$')
    if ($m.Success) {
      $out += [pscustomobject]@{ idx = [int]$m.Groups[1].Value; hwnd = $m.Groups[2].Value; pin = $m.Groups[3].Value; exe = $m.Groups[4].Value; title = $m.Groups[5].Value }
    } else { break }
  }
  return $out
}

$items = ItemsFromLog
if (-not $items -or $items.Count -eq 0) { Write-Output 'could not read the item list from the log'; exit 1 }
$n = $items.Count
$strip = [S]::ByClass('DockStripWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($strip, [ref]$r)
$W = $r.Right - $r.Left
$H = $r.Bottom - $r.Top
$pad = 10; $gap = 6
$icon = [Math]::Min($H - 2 * $pad, 72)
if ($icon -lt 18) { $icon = 18 }
$cell = $icon + $gap
$cap = [int](($W - 2 * $pad + $gap) / $cell)
$show = if ($cap -gt 1) { $cap - 1 } else { $cap }
$visible = [Math]::Min($n, $show)
$total = $visible * $cell
if ($cap -gt 1) { $total += $icon + $gap }
$total -= $gap
$start = $pad + [int](($W - 2 * $pad - $total) / 2)
Write-Output ("strip {0},{1} {2}x{3} icons={4} icon={5} start={6}" -f $r.Left,$r.Top,$W,$H,$n,$icon,$start)

$slot = -1
for ($i = 0; $i -lt $items.Count; $i++) {
  if ($items[$i].exe.ToLower().Contains($Exe.ToLower())) { $slot = $i; break }
}
if ($slot -lt 0) {
  Write-Output ("no slot for " + $Exe + "; items:")
  $items | ForEach-Object { Write-Output ("  [" + $_.idx + "] pin=" + $_.pin + " exe=" + $_.exe + " title=" + $_.title) }
  exit 2
}
Write-Output ("slot $slot = [" + $items[$slot].idx + "] pin=" + $items[$slot].pin + " hwnd=" + $items[$slot].hwnd + " exe=" + $items[$slot].exe + " title=" + $items[$slot].title)
$x = $r.Left + $start + $slot * $cell + [int]($icon / 2)
$y = $r.Top + [int]($H / 2)
Write-Output ("clicking $x,$y")
[S]::MoveTo($x, $y)
Start-Sleep -Milliseconds 600
Show-State 'hovering'
Shot ($Out + '_hover.png')
[S]::LeftClick()
Start-Sleep -Milliseconds 900
Show-State 'after click'
Shot ($Out + '_click.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 10))..($lines.Count - 1)] | Where-Object { $_ -match 'slot=|click|activate|launch|thumb' } | ForEach-Object { Write-Output ("LOG " + $_) }
