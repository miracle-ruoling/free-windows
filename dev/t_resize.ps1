# Reproduction helper: resize the strip to a given geometry, wait, put it back.
# The dock crashed once when the strip was made tall and narrow (0xc0000005).
param([int]$X = 139, [int]$Y = 63, [int]$W = 111, [int]$H = 800, [int]$WaitMs = 2000)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class R {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
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

[R]::SetProcessDPIAware() | Out-Null
$hw = [R]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[R]::GetWindowRect($hw, [ref]$r) | Out-Null
$orig = "$($r.Left),$($r.Top),$($r.Right - $r.Left),$($r.Bottom - $r.Top)"
"orig $orig"

[R]::SetWindowPos($hw, [IntPtr]0, $X, $Y, $W, $H, 0x0014) | Out-Null
Start-Sleep -Milliseconds $WaitMs
$alive = @(Get-Process dock -ErrorAction SilentlyContinue).Count
"after resize to ${W}x${H}: dock alive = $alive"

if ($alive -gt 0) {
    $p = $orig.Split(',')
    [R]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3], 0x0014) | Out-Null
    Start-Sleep -Milliseconds 1200
    "after restore: dock alive = $(@(Get-Process dock -ErrorAction SilentlyContinue).Count)"
}
