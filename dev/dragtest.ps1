# Real drag: press on the strip's blank area, move the mouse, release. Uses the physical
# button state (the dock's drag detection reads GetAsyncKeyState), so this exercises the
# same path a human does.
param([int]$Dx = 120, [int]$Dy = 0, [int]$Steps = 20)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class DG {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static IntPtr Find(string cls) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(h, sb, 256);
            if (sb.ToString() == cls) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
[DG]::SetProcessDPIAware() | Out-Null
$hw = [DG]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[DG]::GetWindowRect($hw, [ref]$r) | Out-Null
$before = "$($r.Left),$($r.Top)"
# a point in the strip's blank left padding (icons start further right)
$x0 = $r.Left + 24
$y0 = $r.Top + [int](($r.Bottom - $r.Top) / 2)
[DG]::SetCursorPos($x0, $y0) | Out-Null
Start-Sleep -Milliseconds 400
[DG]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)     # LEFTDOWN
Start-Sleep -Milliseconds 80
for ($i = 1; $i -le $Steps; $i++) {
    [DG]::SetCursorPos($x0 + [int]($Dx * $i / $Steps), $y0 + [int]($Dy * $i / $Steps)) | Out-Null
    Start-Sleep -Milliseconds 20
}
Start-Sleep -Milliseconds 120
[DG]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)     # LEFTUP
Start-Sleep -Milliseconds 400
[DG]::GetWindowRect($hw, [ref]$r) | Out-Null
"drag $before -> $($r.Left),$($r.Top)  (asked for +$Dx,$Dy)"
