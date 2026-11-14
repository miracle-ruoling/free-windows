param([string]$Exe = 'echomusic', [string]$Out = 't_itempick')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
function CloseGridByClick() {
  if (-not (GridVisible)) { return }
  [S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 120; [S]::LeftClick()
  Start-Sleep -Milliseconds 350
}

if (-not (Wait-Idle 1500 45)) { Write-Output 'user busy - aborted'; exit 1 }
$before = -1
for ($try = 1; $try -le 3; $try++) {
  CloseGridByClick
  if (GridVisible) { Write-Output ("try ${try}: panel still open after the outside click"); Start-Sleep -Milliseconds 400; continue }
  $before = (Get-LogLines).Count
  if (-not (Open-Grid)) { Write-Output ("try ${try}: grid did not open"); Start-Sleep -Milliseconds 400; continue }
  Start-Sleep -Milliseconds 500
  $probe = @(Get-LogLines)
  $got = $false
  if ($probe.Count -gt $before) {
    foreach ($l in $probe[$before..($probe.Count - 1)]) { if ($l -match "tray\[\d+\] tip=") { $got = $true; break } }
  }
  if ($got) { Write-Output ("fresh tray block after try $try"); break }
  Write-Output ("try ${try}: no fresh tray block")
}
if ($before -lt 0) { Write-Output 'could not get a fresh grid'; exit 1 }
$lines = Get-LogLines
# The log prints tray[i] in *pre-sort* order, the cells are in sorted-by-tip order,
# so rebuild the sort here with an ordinal comparison (UTF-16 code units, like std::wstring).
$entries = New-Object System.Collections.ArrayList
if ($lines.Count -gt $before) {
  foreach ($l in $lines[$before..($lines.Count - 1)]) {
    $m = [regex]::Match($l, "tray\[(\d+)\] tip='([^']*)' exe=([^ ]+)")
    if ($m.Success) { [void]$entries.Add([pscustomobject]@{ tip = $m.Groups[2].Value; exe = $m.Groups[3].Value }) }
  }
}
if ($entries.Count -eq 0) { Write-Output 'no fresh tray map (grid was already open?)'; exit 2 }
$sorted = @($entries.ToArray())
# strict ordinal compare (UTF-16 code units), same as std::wstring's operator<
for ($i = 0; $i -lt $sorted.Count; $i++) {
  for ($j = 0; $j -lt $sorted.Count - 1 - $i; $j++) {
    if ([string]::CompareOrdinal($sorted[$j].tip, $sorted[$j + 1].tip) -gt 0) {
      $t = $sorted[$j]; $sorted[$j] = $sorted[$j + 1]; $sorted[$j + 1] = $t
    }
  }
}
$map = @{}
for ($i = 0; $i -lt $sorted.Count; $i++) { $map[$i] = $sorted[$i].exe }
$cell = -1
foreach ($k in ($map.Keys | Sort-Object)) {
  if ($map[$k].ToLower().Contains($Exe.ToLower())) { $cell = $k; break }
}
if ($cell -lt 0) {
  Write-Output ("no cell for " + $Exe + "; cells:")
  $map.Keys | Sort-Object | ForEach-Object { Write-Output ("  " + $_ + " = " + $map[$_]) }
  exit 3
}

$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
Write-Output ("cell $cell (" + $map[$cell] + ") -> $cx,$cy")
[S]::MoveTo($cx, $cy)
Start-Sleep -Milliseconds 300
$beforeMenu = (Get-LogLines).Count
[S]::RightClick()
Start-Sleep -Milliseconds 900
$mr = $null
$fresh = @(Get-LogLines)
if ($fresh.Count -gt $beforeMenu) {
  $mx = -1; $my = -1; $mw = 0; $mh = 0
  foreach ($l in $fresh[$beforeMenu..($fresh.Count - 1)]) {
    $m = [regex]::Match($l, 'appeared at (-?\d+),(-?\d+) \((\d+)x(\d+)\)')
    if ($m.Success) { $mx = [int]$m.Groups[1].Value; $my = [int]$m.Groups[2].Value; $mw = [int]$m.Groups[3].Value; $mh = [int]$m.Groups[4].Value }
    $m2 = [regex]::Match($l, 'moved the menu itself to (-?\d+),(-?\d+)')
    if ($m2.Success) { $mx = [int]$m2.Groups[1].Value; $my = [int]$m2.Groups[2].Value }
  }
  if ($mx -ge 0) { $mr = @($mx, $my, $mw, $mh) }
}
if (-not $mr) { Write-Output 'no menu rect'; exit 4 }
Write-Output ("menu at {0},{1} {2}x{3}" -f $mr[0],$mr[1],$mr[2],$mr[3])
Shot ($Out + '_menu.png')
[S]::MoveTo(($mr[0] + 50), ($mr[1] + 22))
Start-Sleep -Milliseconds 250
[S]::LeftClick()
Start-Sleep -Milliseconds 250
Write-Output ("+250ms gridVisible=" + (GridVisible))
Start-Sleep -Milliseconds 550
Write-Output ("+800ms gridVisible=" + (GridVisible))
Start-Sleep -Milliseconds 900
Write-Output ("+1700ms gridVisible=" + (GridVisible))
Shot ($Out + '_after.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 12))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|grid:|press:' } | ForEach-Object { Write-Output ("LOG " + $_) }
