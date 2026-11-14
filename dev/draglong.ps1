# Hold a real drag for N seconds (button down the whole time) so the 10s frame-stats line
# is dominated by drag frames.
param([int]$Seconds = 12, [int]$Span = 120)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class DL {
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
[DL]::SetProcessDPIAware() | Out-Null
$hw = [DL]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[DL]::GetWindowRect($hw, [ref]$r) | Out-Null
$x0 = $r.Left + 30
$y0 = $r.Top + [int](($r.Bottom - $r.Top) / 2)
[DL]::SetCursorPos($x0, $y0) | Out-Null
Start-Sleep -Milliseconds 400
[DL]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $dx = [int]($Span * [Math]::Sin($i / 8.0))
    [DL]::SetCursorPos($x0 + $dx, $y0) | Out-Null
    Start-Sleep -Milliseconds 12
    $i++
}
[DL]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 300
"dragged for $([math]::Round($sw.Elapsed.TotalSeconds,1))s in $i steps"
