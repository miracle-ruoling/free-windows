param([int]$X = 1200, [int]$Y = 300, [int]$HoldMs = 120)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int size);
[StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Explicit)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(4)] public MOUSEINPUT mi; }
"@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 350
$down = New-Object 'W.U+INPUT[]' 1
$down[0].type = 0
$down[0].mi.dwFlags = 0x0008   # RIGHTDOWN
$up = New-Object 'W.U+INPUT[]' 1
$up[0].type = 0
$up[0].mi.dwFlags = 0x0010     # RIGHTUP
[void][W.U]::SendInput(1, $down, [System.Runtime.InteropServices.Marshal]::SizeOf([type]'W.U+INPUT'))
Start-Sleep -Milliseconds $HoldMs
[void][W.U]::SendInput(1, $up, [System.Runtime.InteropServices.Marshal]::SizeOf([type]'W.U+INPUT'))
Write-Output ("SendInput right click at $X,$Y (hold ${HoldMs}ms)")
