param([int]$X = 1120, [int]$Y = 289, [int]$MoveAfterMs = 30)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
"@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 300
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 90
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $MoveAfterMs
[void][W.U]::SetCursorPos(956, 951)     # move away immediately, like a human would
Write-Output ("clicked $X,$Y then moved away after ${MoveAfterMs}ms")
