param([int]$Cell = 3, [string]$Out = 't_iconclick.png')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
if (-not (Open-Grid)) { Write-Output 'grid did not open'; exit 1 }
Start-Sleep -Milliseconds 400
$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($Cell / $cols); $col = $Cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
Write-Output ("grid {0},{1} {2} px cols={3} cell {4} -> {5},{6}" -f $r.Left,$r.Top,$gw,$cols,$Cell,$cx,$cy)
Show-State 'before click'
[S]::MoveTo($cx, $cy)
Start-Sleep -Milliseconds 300
[S]::LeftClick()
Start-Sleep -Milliseconds 1200
Show-State 'after click'
Shot $Out
Write-Output ('saved ' + $Out)
