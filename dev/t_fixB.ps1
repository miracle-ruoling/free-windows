param([string]$Out = 't_fixB')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function LogLines() {
  $p = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
  try {
    $fs = New-Object System.IO.FileStream($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
    return ($txt -split "`r?`n")
  } catch { return @() }
}
function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
function LastMenuRect() {
  # "tray: menu 000...02A0C80 appeared at 1030,454 (279x182), pointer untouched at ..."
  $lines = LogLines
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $m = [regex]::Match($lines[$i], 'appeared at (\d+),(\d+) \((\d+)x(\d+)\)')
    if ($m.Success) {
      return @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$m.Groups[4].Value)
    }
  }
  return $null
}

if (-not (Wait-Idle 1500 60)) { Write-Output 'user is busy - aborted'; exit 1 }
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 400
$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
Write-Output ("grid {0},{1} {2}px cols={3}" -f $r.Left,$r.Top,$gw,$cols)

# cell 1 = echomusic -> its menu has "打开主窗口" as the first item
$cx = $r.Left + 14 + 1 * 66 + 30
$cy = $r.Top + 14 + 30
[S]::MoveTo($cx, $cy)
Start-Sleep -Milliseconds 300
[S]::RightClick()
Start-Sleep -Milliseconds 900
Show-State 'menu opened'
$mr = LastMenuRect
if (-not $mr) { Write-Output 'no menu rect in log'; exit 2 }
Write-Output ("menu rect {0},{1} {2}x{3}" -f $mr[0],$mr[1],$mr[2],$mr[3])
Shot ($Out + '_menu.png')

# click the first item
[S]::MoveTo(($mr[0] + 45), ($mr[1] + 22))
Start-Sleep -Milliseconds 250
[S]::LeftClick()
Start-Sleep -Milliseconds 200
Write-Output ("+200ms gridVisible=" + (GridVisible))
Start-Sleep -Milliseconds 500
Write-Output ("+700ms gridVisible=" + (GridVisible))
Start-Sleep -Milliseconds 800
Write-Output ("+1500ms gridVisible=" + (GridVisible))
Shot ($Out + '_after.png')
$lines = LogLines
$lines[([Math]::Max(0, $lines.Count - 12))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|grid:|press:' } | ForEach-Object { Write-Output ("LOG " + $_) }
