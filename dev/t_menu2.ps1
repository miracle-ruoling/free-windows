param([string]$Out = 't_menu')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
function GridR() { $g = [S]::ByClass('DockGridWindow'); $r = New-Object S+RECT; [void][S]::GetWindowRect($g, [ref]$r); return $r }
function CellXY($r, $cell) {
  $gw = $r.Right - $r.Left; $cols = [int](($gw - 28 + 6) / 66)
  $row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
  return @(($r.Left + 14 + $col * 66 + 30), ($r.Top + 14 + $row * 66 + 30))
}

Write-Output '--- A: right click cell 2, then right click cell 3 (menu should be replaced)'
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 300
$r = GridR
$c = CellXY $r 2
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 900
Show-State 'A1 menu on cell2'
Shot ($Out + '_A1.png')
$c = CellXY $r 3
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 900
Show-State 'A2 menu on cell3'
Shot ($Out + '_A2.png')

Write-Output '--- B: left click empty panel padding (menu should close, panel stays)'
$r = GridR
[S]::MoveTo(($r.Left + 4), ($r.Top + 4)); Start-Sleep -Milliseconds 200; [S]::LeftClick()
Start-Sleep -Milliseconds 600
Show-State 'B blank click'
Shot ($Out + '_B.png')

Write-Output '--- C: right click cell 2 again, then left click far outside (all gone)'
$r = GridR
$c = CellXY $r 2
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 900
Show-State 'C1 menu open'
[S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 200; [S]::LeftClick()
Start-Sleep -Milliseconds 600
Show-State 'C2 after outside click'
Shot ($Out + '_C2.png')
