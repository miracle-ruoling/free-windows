param([string]$Out = 't_fix')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
function GridR() { $g = [S]::ByClass('DockGridWindow'); $r = New-Object S+RECT; [void][S]::GetWindowRect($g, [ref]$r); return $r }
function CellXY($r, $cell) {
  $gw = $r.Right - $r.Left; $cols = [int](($gw - 28 + 6) / 66)
  $row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
  return @(($r.Left + 14 + $col * 66 + 30), ($r.Top + 14 + $row * 66 + 30))
}

Write-Output '--- A (2c-ii): right click empty space inside the panel -> panel must stay'
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 350
$r = GridR
[S]::MoveTo(($r.Left + 5), ($r.Top + 5)); Start-Sleep -Milliseconds 200; [S]::RightClick()
Start-Sleep -Milliseconds 600
Show-State 'A right click panel padding'
Shot ($Out + '_A.png')

Write-Output '--- B (3c-i): menu open, left click outside on another app -> everything gone at once'
$r = GridR
$c = CellXY $r 2
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 800
Show-State 'B1 menu open'
[S]::MoveTo(700, 700); Start-Sleep -Milliseconds 150; [S]::LeftClick()
Start-Sleep -Milliseconds 120
Show-State 'B2 +120ms'
Start-Sleep -Milliseconds 300
Show-State 'B3 +420ms'
Shot ($Out + '_B.png')
