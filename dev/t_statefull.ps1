param([string]$Out = 'statefull')
# End-to-end walk through the interaction state machine. Prints one line per step so the
# dock log can be correlated (log lines carry the same order).
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

function GridRect() {
  $g = [S]::ByClass('DockGridWindow')
  $r = New-Object S+RECT
  [void][S]::GetWindowRect($g, [ref]$r)
  return $r
}
function CellPt($r, $cell) {
  $gw = $r.Right - $r.Left
  $cols = [int](($gw - 28 + 6) / 66)
  $row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
  return @(($r.Left + 14 + $col * 66 + 30), ($r.Top + 14 + $row * 66 + 30))
}
function MenuInfo() {
  # the app's menu is the extra visible popup that is not ours; report its rect
  $res = 'no-menu'
  return $res
}

Write-Output '--- step 1: open panel'
if (-not (Open-Grid)) { Write-Output 'grid did not open'; exit 1 }
Start-Sleep -Milliseconds 400
Show-State '1 open'

Write-Output '--- step 2: pointer far away, no click (expect grid stays)'
[S]::MoveTo(1800, 1000)
Start-Sleep -Milliseconds 1200
Show-State '2 far'

Write-Output '--- step 3: left click on empty desktop (expect grid gone instantly)'
[S]::MoveTo(8, 1060)
Start-Sleep -Milliseconds 120
[S]::LeftClick()
Start-Sleep -Milliseconds 300
Show-State '3 clicked outside'

Write-Output '--- step 4: reopen, right click cell 2 (expect menu + panel stays)'
if (-not (Open-Grid)) { Write-Output 'grid did not reopen'; exit 1 }
Start-Sleep -Milliseconds 400
$r = GridRect
$c = CellPt $r 2
[S]::MoveTo($c[0], $c[1])
Start-Sleep -Milliseconds 250
[S]::RightClick()
Start-Sleep -Milliseconds 900
Show-State '4 menu open'
Shot ($Out + '_4.png')

Write-Output '--- step 5: pointer far away with menu open (expect all three stay)'
[S]::MoveTo(1800, 1000)
Start-Sleep -Milliseconds 1200
Show-State '5 far with menu'
Shot ($Out + '_5.png')

Write-Output '--- step 6: left click on empty panel space (expect menu closes, panel stays)'
$r = GridRect
[S]::MoveTo(($r.Left + 4), ($r.Top + 4))
Start-Sleep -Milliseconds 150
[S]::LeftClick()
Start-Sleep -Milliseconds 500
Show-State '6 blank in panel'
Shot ($Out + '_6.png')

Write-Output '--- step 7: right click cell 3 then cell 4 (expect menu replaced each time, panel stays)'
$r = GridRect
$c = CellPt $r 3
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 200; [S]::RightClick()
Start-Sleep -Milliseconds 800
Show-State '7a menu cell3'
$c = CellPt $r 4
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 200; [S]::RightClick()
Start-Sleep -Milliseconds 800
Show-State '7b menu cell4'
Shot ($Out + '_7.png')

Write-Output '--- step 8: right click the same cell again (expect refresh, panel stays)'
$c = CellPt $r 4
[S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 200; [S]::RightClick()
Start-Sleep -Milliseconds 800
Show-State '8 same cell again'
Shot ($Out + '_8.png')

Write-Output '--- step 9: left click elsewhere (expect menu+panel gone)'
[S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 120; [S]::LeftClick()
Start-Sleep -Milliseconds 400
Show-State '9 outside with menu'
