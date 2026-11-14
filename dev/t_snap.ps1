# Edge-docking check: put the strip at an edge, park the cursor on it (the strip is
# invisible otherwise), and read the four corner pixels off the screen. A square corner
# shows the glass there; a rounded corner shows whatever is behind the strip.
param([int]$Margin = 40)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public struct POINT { public int X; public int Y; }
public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
public class S {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
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

[S]::SetProcessDPIAware() | Out-Null
$hw = [S]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[S]::GetWindowRect($hw, [ref]$r) | Out-Null
$orig = "$($r.Left),$($r.Top),$($r.Right - $r.Left),$($r.Bottom - $r.Top)"
$W = $r.Right - $r.Left; $H = $r.Bottom - $r.Top
$mi = New-Object MONITORINFO
$mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
[S]::GetMonitorInfo([S]::MonitorFromWindow($hw, 2), [ref]$mi) | Out-Null
$wa = $mi.rcWork
$old = New-Object POINT
[S]::GetCursorPos([ref]$old) | Out-Null

function Pixel([int]$x, [int]$y) {
    $bmp = New-Object System.Drawing.Bitmap 1, 1
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size 1, 1))
    $c = $bmp.GetPixel(0, 0)
    $g.Dispose(); $bmp.Dispose()
    return ('{0:x2}{1:x2}{2:x2}' -f $c.R, $c.G, $c.B)
}

function PlaceAndSample([string]$name, [int]$x, [int]$y) {
    [S]::SetWindowPos($hw, [IntPtr]0, $x, $y, $W, $H, 0x0014) | Out-Null
    Start-Sleep -Milliseconds 150
    [S]::SetCursorPos($x + [int]($W / 2), $y + [int]($H / 2)) | Out-Null   # make it opaque
    Start-Sleep -Milliseconds 450
    $tl = Pixel ($x + 2) ($y + 2)
    $tr = Pixel ($x + $W - 3) ($y + 2)
    $bl = Pixel ($x + 2) ($y + $H - 3)
    $br = Pixel ($x + $W - 3) ($y + $H - 3)
    $mid = Pixel ($x + [int]($W / 2)) ($y + 3)
    "{0,-22} at {1},{2} -> TL={3} TR={4} BL={5} BR={6} (top-mid={7})" -f $name, $x, $y, $tl, $tr, $bl, $br, $mid
}

PlaceAndSample 'free (no edge)' ($wa.Left + $Margin) ($wa.Top + [int]($wa.Bottom / 2) - [int]($H / 2))
PlaceAndSample 'top edge'      ($wa.Left + $Margin) $wa.Top
PlaceAndSample 'bottom edge'   ($wa.Left + $Margin) ($wa.Bottom - $H)

$p = $orig.Split(',')
[S]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3], 0x0014) | Out-Null
Start-Sleep -Milliseconds 300
[S]::SetCursorPos($old.X, $old.Y) | Out-Null
"restored to $orig"

"--- log ---"
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
Get-Content $log | Where-Object { $_ -match 'snap: corners' } | Select-Object -Last 6
