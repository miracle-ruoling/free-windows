param([int]$X = 1120, [int]$Y = 289, [int]$Settle = 50, [int]$Hold = 600)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
"@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds $Settle
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $Hold
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
Write-Output ("slow click at $X,$Y settle=$Settle hold=$Hold")
