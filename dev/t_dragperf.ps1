# Simulate a drag: move the strip back and forth while the cursor sits on it, so the
# glass has to re-bake every frame. Used to check bake cost / refresh rate.
param([int]$Seconds = 8, [int]$Y = 300)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class D2 {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int m);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
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
[D2]::SetProcessDPIAware() | Out-Null
$hw = [D2]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[D2]::GetWindowRect($hw, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$orig = "$($r.Left),$($r.Top)"
[D2]::SetCursorPos(800, $Y + [int]($h / 2)) | Out-Null
Start-Sleep -Milliseconds 300

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $x = 400 + [int](120 * [Math]::Sin($i / 6.0))
    [D2]::SetWindowPos($hw, [IntPtr]0, $x, $Y, $w, $h, 0x0014) | Out-Null
    Start-Sleep -Milliseconds 15
    $i++
}
$p = $orig.Split(',')
[D2]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], $w, $h, 0x0014) | Out-Null
"moved $i steps in $([math]::Round($sw.Elapsed.TotalSeconds,1))s, restored to $orig"
