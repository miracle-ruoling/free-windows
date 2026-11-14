param([int]$X = 8, [int]$Y = 1060)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
Show-State 'before'
Write-Output 'moving'
[S]::MoveTo($X, $Y)
Start-Sleep -Milliseconds 200
$p = New-Object S+POINT
[void][S]::GetCursorPos([ref]$p)
Write-Output ("cursor now {0},{1}" -f $p.X, $p.Y)
Write-Output 'clicking'
[S]::LeftClick()
Start-Sleep -Milliseconds 500
Show-State 'after click'
