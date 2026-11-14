param([string]$Exe = 'powershell', [string]$Out = 't_hidespeed')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
if (-not (Wait-Idle 1500 45)) { Write-Output 'user busy - aborted'; exit 1 }
if (GridVisible) { [S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 120; [S]::LeftClick(); Start-Sleep -Milliseconds 400 }
$before = (Get-LogLines).Count
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 500
$lines = Get-LogLines
$entries = New-Object System.Collections.ArrayList
foreach ($l in $lines[$before..($lines.Count - 1)]) {
  $m = [regex]::Match($l, "tray\[(\d+)\] tip='([^']*)' exe=([^ ]+)")
  if ($m.Success) { [void]$entries.Add([pscustomobject]@{ tip = $m.Groups[2].Value; exe = $m.Groups[3].Value }) }
}
$sorted = @($entries.ToArray())
for ($i = 0; $i -lt $sorted.Count; $i++) {
  for ($j = 0; $j -lt $sorted.Count - 1 - $i; $j++) {
    if ([string]::CompareOrdinal($sorted[$j].tip, $sorted[$j + 1].tip) -gt 0) { $t = $sorted[$j]; $sorted[$j] = $sorted[$j + 1]; $sorted[$j + 1] = $t }
  }
}
$cell = -1
for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].exe.ToLower().Contains($Exe)) { $cell = $i; break } }
if ($cell -lt 0) { Write-Output ("no cell for $Exe"); exit 2 }
$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
[S]::MoveTo($cx, $cy); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 900
Write-Output ("menu open, panel visible=" + (GridVisible))
Shot ($Out + '_1menu.png')

# now click outside: measure how long the panel stays visible afterwards
[S]::MoveTo(8, 1060)
Start-Sleep -Milliseconds 150
$t0 = [Diagnostics.Stopwatch]::StartNew()
[S]::LeftClick()
$firstHidden = -1
for ($i = 0; $i -lt 300; $i++) {
  if (-not (GridVisible)) { $firstHidden = $t0.ElapsedMilliseconds; break }
  Start-Sleep -Milliseconds 10
}
Write-Output ("panel invisible after " + $firstHidden + " ms")
Start-Sleep -Milliseconds 400
Write-Output ("+400ms visible=" + (GridVisible))
Shot ($Out + '_2after.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 10))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|grid:|press:' } | ForEach-Object { Write-Output ("LOG " + $_) }
