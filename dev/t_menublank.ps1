param([string]$Exe = 'qq', [string]$Out = 't_menublank', [int]$FromBottom = 4)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
function MenuPresent() {
  # a visible popup that is not ours paints over the panel; just check the dock log
  $lines = Get-LogLines
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match 'app menu is gone') { return $false }
    if ($lines[$i] -match 'watching menu window') { return $true }
    if ($lines[$i] -match 'grid: hide') { return $false }
  }
  return $false
}

if (-not (Wait-Idle 1500 45)) { Write-Output 'user busy - aborted'; exit 1 }
if (GridVisible) { [S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 120; [S]::LeftClick(); Start-Sleep -Milliseconds 350 }
$before = (Get-LogLines).Count
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 500

$lines = Get-LogLines
$entries = New-Object System.Collections.ArrayList
if ($lines.Count -gt $before) {
  foreach ($l in $lines[$before..($lines.Count - 1)]) {
    $m = [regex]::Match($l, "tray\[(\d+)\] tip='([^']*)' exe=([^ ]+)")
    if ($m.Success) { [void]$entries.Add([pscustomobject]@{ tip = $m.Groups[2].Value; exe = $m.Groups[3].Value }) }
  }
}
if ($entries.Count -eq 0) { Write-Output 'no fresh tray map'; exit 2 }
$sorted = @($entries.ToArray())
for ($i = 0; $i -lt $sorted.Count; $i++) {
  for ($j = 0; $j -lt $sorted.Count - 1 - $i; $j++) {
    if ([string]::CompareOrdinal($sorted[$j].tip, $sorted[$j + 1].tip) -gt 0) {
      $t = $sorted[$j]; $sorted[$j] = $sorted[$j + 1]; $sorted[$j + 1] = $t
    }
  }
}
$cell = -1
for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].exe.ToLower().Contains($Exe)) { $cell = $i; break } }
if ($cell -lt 0) { Write-Output ("no cell for " + $Exe); for ($i = 0; $i -lt $sorted.Count; $i++) { Write-Output ("  $i = " + $sorted[$i].exe) }; exit 3 }

$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
Write-Output ("cell $cell (" + $sorted[$cell].exe + ") -> $cx,$cy")

$beforeMenu = (Get-LogLines).Count
[S]::MoveTo($cx, $cy)
Start-Sleep -Milliseconds 250
[S]::RightClick()
Start-Sleep -Milliseconds 900
$fresh = @(Get-LogLines)
$mx = -1; $my = -1; $mw = 0; $mh = 0
if ($fresh.Count -gt $beforeMenu) {
  foreach ($l in $fresh[$beforeMenu..($fresh.Count - 1)]) {
    $m = [regex]::Match($l, 'appeared at (-?\d+),(-?\d+) \((\d+)x(\d+)\)')
    if ($m.Success) { $mx = [int]$m.Groups[1].Value; $my = [int]$m.Groups[2].Value; $mw = [int]$m.Groups[3].Value; $mh = [int]$m.Groups[4].Value }
    $m2 = [regex]::Match($l, 'moved the menu itself to (-?\d+),(-?\d+)')
    if ($m2.Success) { $mx = [int]$m2.Groups[1].Value; $my = [int]$m2.Groups[2].Value }
  }
}
if ($mx -lt 0) { Write-Output 'no menu rect'; exit 4 }
Write-Output ("menu at $mx,$my ${mw}x${mh}")
Shot ($Out + '_menu.png')
Write-Output ("menu present before click = " + (MenuPresent))
# click inside the menu but on its bottom margin (not an item): this exercises
# "a press on the app menu" without choosing a command
$px = $mx + [int]($mw / 2)
$py = $my + $mh - $FromBottom
Write-Output ("click at $px,$py")
[S]::MoveTo($px, $py)
Start-Sleep -Milliseconds 200
[S]::LeftClick()
Start-Sleep -Milliseconds 300
Write-Output ("+300ms gridVisible=" + (GridVisible) + " menuPresent=" + (MenuPresent))
Start-Sleep -Milliseconds 700
Write-Output ("+1000ms gridVisible=" + (GridVisible) + " menuPresent=" + (MenuPresent))
Start-Sleep -Milliseconds 900
Write-Output ("+1900ms gridVisible=" + (GridVisible) + " menuPresent=" + (MenuPresent))
Shot ($Out + '_after.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 12))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|grid:|press:' } | ForEach-Object { Write-Output ("LOG " + $_) }
