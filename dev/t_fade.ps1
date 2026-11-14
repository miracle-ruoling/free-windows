# Two captures of the same strip position: cursor on the strip (fade alpha = 255) and
# cursor 80px below it (alpha ~119, the "parked" state). Shows how much of the sharp
# desktop the fade lets through, independent of the glass itself.
param([int]$X = 650, [int]$Y = 0, [int]$W = 906, [int]$H = 111)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class FD {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
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
[FD]::SetProcessDPIAware() | Out-Null
$hw = [FD]::Find('DockStripWindow')
$r = New-Object RECT
[FD]::GetWindowRect($hw, [ref]$r) | Out-Null

function Shot([int]$cx, [int]$cy, [string]$out) {
    [FD]::SetCursorPos($cx, $cy) | Out-Null
    Start-Sleep -Milliseconds 700
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
    $p = Join-Path $PSScriptRoot $out
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    # what the fade computed for this cursor position
    $dx = [Math]::Max(0, [Math]::Max($r.Left - $cx, $cx - $r.Right))
    $dy = [Math]::Max(0, [Math]::Max($r.Top - $cy, $cy - $r.Bottom))
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    "$out  cursor=$cx,$cy distance=$([math]::Round($d,1)) -> expected alpha ~ " +
      "$([math]::Round([Math]::Min(255, [Math]::Max(0, 255 - ($d - 0) * 255 / 150))))"
}

Shot ($r.Left + [int](($r.Right - $r.Left) / 2)) ($r.Top + [int](($r.Bottom - $r.Top) / 2)) 'fade_on.png'
Shot ($r.Left + [int](($r.Right - $r.Left) / 2)) ($r.Bottom + 80) 'fade_parked.png'
