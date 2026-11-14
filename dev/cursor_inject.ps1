Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll", SetLastError=true)] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
$ok = [W.U]::SetCursorPos(1000, 400)
Write-Output ("SetCursorPos ok=" + $ok + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
$w = [W.U]::GetSystemMetrics(0); $h = [W.U]::GetSystemMetrics(1)
Write-Output ("screen " + $w + "x" + $h)
# absolute move via mouse_event (0x8000 = MOVE, 0x0001 = ABSOLUTE)
$ax = [int](1000 * 65535 / ($w - 1)); $ay = [int](400 * 65535 / ($h - 1))
[W.U]::mouse_event(0x8001, $ax, $ay, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 200
$p = New-Object W.U+POINT
[void][W.U]::GetCursorPos([ref]$p)
Write-Output ("after mouse_event abs -> " + $p.X + "," + $p.Y + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
# inject a right click at the current position
[W.U]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[W.U]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "clicked right"
