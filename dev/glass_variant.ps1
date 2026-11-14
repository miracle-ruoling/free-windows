# Set glass settings in dock.ini, restart the dock, park the strip at (650,0) with the
# cursor on it, and capture a 906x111 crop. Used to compare glass looks side by side.
param([int]$Opacity = 235, [int]$Tint = 143, [string]$Out = "variant.png",
      [int]$X = 650, [int]$Y = 0, [int]$W = 906, [int]$H = 111)

$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
(Get-Content $ini) -replace '^glassOpacity=.*', "glassOpacity=$Opacity" `
                   -replace '^tintStrength=.*', "tintStrength=$Tint" | Set-Content $ini -Encoding ASCII
Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Start-Process $exe
Start-Sleep -Milliseconds 1800
& (Join-Path $PSScriptRoot 'diag_glass.ps1') -X $X -Y $Y -W $W -H $H -Out $Out
