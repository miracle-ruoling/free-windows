param([int]$X = 16, [int]$Y = 16)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
[void][W.U]::SetProcessDPIAware()
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
if ($h -eq [IntPtr]::Zero) { Write-Output 'no strip'; exit 1 }
$p = New-Object W.U+POINT
$p.X = $X; $p.Y = $Y
[void][W.U]::ClientToScreen($h, [ref]$p)
[void][W.U]::SetCursorPos($p.X, $p.Y)
Start-Sleep -Milliseconds 400
[W.U]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
Start-Sleep -Milliseconds 120
[W.U]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
Write-Output ("real click at " + $p.X + "," + $p.Y)
