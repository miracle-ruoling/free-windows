$ErrorActionPreference = 'Stop'
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
'@
[void][W.U]::SetProcessDPIAware()
# park the cursor far away so the strip fades back out and the grid closes
[void][W.U]::SetCursorPos(200, 900)
Start-Sleep -Milliseconds 900
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'fullshot.ps1') -Out $args[0]
