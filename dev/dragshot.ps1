# Drag the strip slowly and grab a screenshot *while the button is still down*, including
# some screen above the strip: the text above the top edge is the true backdrop, the text
# inside the strip comes from the snapshot. If they line up, the glass is anchored.
param([int]$Dx = 60, [int]$Steps = 12, [string]$Out = "middrag.png")

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class DC {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
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
[DC]::SetProcessDPIAware() | Out-Null
$hw = [DC]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[DC]::GetWindowRect($hw, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$start = "$($r.Left),$($r.Top)"
$y0 = $r.Top + [int]($h / 2)
$x0 = $r.Left + 24
[DC]::SetCursorPos($x0, $y0) | Out-Null
Start-Sleep -Milliseconds 400
[DC]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
for ($i = 1; $i -le $Steps; $i++) {
    [DC]::SetCursorPos($x0 + [int]($Dx * $i / $Steps), $y0) | Out-Null
    Start-Sleep -Milliseconds 25
}
# still holding the button: grab the strip plus 40px above it
[DC]::GetWindowRect($hw, [ref]$r) | Out-Null
$capY = [Math]::Max(0, $r.Top - 40)
$capH = ($r.Bottom - $capY) + 10
$bmp = New-Object System.Drawing.Bitmap 700, $capH
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $capY, 0, 0, (New-Object System.Drawing.Size 700, $capH))
$g.Dispose()
$bmp.Save((Join-Path $PSScriptRoot $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"captured while dragging at $($r.Left),$($r.Top)  (from $start, +$Dx asked)"
[DC]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 300
