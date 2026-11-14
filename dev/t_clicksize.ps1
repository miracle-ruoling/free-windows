# Reproduce: resize the strip tall and narrow, then post a click near the bottom
# (the earlier crash happened while the strip was 111x800 and a posted click followed).
param([int]$W = 111, [int]$H = 800, [int]$Cx = 56, [int]$Cy = 999)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class R2 {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
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

[R2]::SetProcessDPIAware() | Out-Null
$hw = [R2]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[R2]::GetWindowRect($hw, [ref]$r) | Out-Null
$orig = "$($r.Left),$($r.Top),$($r.Right - $r.Left),$($r.Bottom - $r.Top)"

[R2]::SetWindowPos($hw, [IntPtr]0, 139, 63, $W, $H, 0x0014) | Out-Null
Start-Sleep -Milliseconds 800
"resized; alive = $(@(Get-Process dock -ErrorAction SilentlyContinue).Count)"

$lp = [IntPtr](($Cy -shl 16) -bor ($Cx -band 0xFFFF))
[R2]::PostMessage($hw, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 40
[R2]::PostMessage($hw, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 600
"after click at $Cx,$Cy : alive = $(@(Get-Process dock -ErrorAction SilentlyContinue).Count)"

if (@(Get-Process dock -ErrorAction SilentlyContinue).Count -gt 0) {
    $p = $orig.Split(',')
    [R2]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3], 0x0014) | Out-Null
    Start-Sleep -Milliseconds 800
    "restored; alive = $(@(Get-Process dock -ErrorAction SilentlyContinue).Count)"
}
