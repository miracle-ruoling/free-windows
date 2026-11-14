# Move the strip, park the cursor on it (so it is opaque), wait, and capture a crop.
param([int]$X = 139, [int]$Y = 300, [int]$W = 800, [int]$H = 120,
      [string]$Out = "glass.png", [int]$WaitMs = 600, [switch]$NoCursor)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class M {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
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
[M]::SetProcessDPIAware() | Out-Null
$hw = [M]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[M]::GetWindowRect($hw, [ref]$r) | Out-Null
$sw = $r.Right - $r.Left; $sh = $r.Bottom - $r.Top
[M]::SetWindowPos($hw, [IntPtr]0, $X, $Y, $sw, $sh, 0x0014) | Out-Null
Start-Sleep -Milliseconds 200
if (-not $NoCursor) { [M]::SetCursorPos($X + [int]($sw / 2), $Y + [int]($sh / 2)) | Out-Null }
Start-Sleep -Milliseconds $WaitMs

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
$g.Dispose()
$path = Join-Path $PSScriptRoot $Out
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"strip at $X,$Y (${sw}x${sh}) -> $path"
