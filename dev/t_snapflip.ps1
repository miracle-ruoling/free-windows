# Snap + dodge: park the strip on the top edge (square top corners), double-click it
# with the dodge path, and check that it lands on the bottom edge with the bottom
# corners square. Leaves the strip where it was and restores dock.ini.
param([int]$X = 40, [int]$Y = 0)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class SF {
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

[SF]::SetProcessDPIAware() | Out-Null
$hw = [SF]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[SF]::GetWindowRect($hw, [ref]$r) | Out-Null
$orig = "$($r.Left),$($r.Top),$($r.Right - $r.Left),$($r.Bottom - $r.Top)"
$W = $r.Right - $r.Left; $H = $r.Bottom - $r.Top
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'

[SF]::SetWindowPos($hw, [IntPtr]0, $X, $Y, $W, $H, 0x0014) | Out-Null
Start-Sleep -Milliseconds 600
"placed at $X,$Y (top edge)"

# double click the left padding (blank strip), same point t_flip uses
$cx = 40; $cy = [int]($H / 2)
$lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
[SF]::PostMessage($hw, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 25
[SF]::PostMessage($hw, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 120
[SF]::PostMessage($hw, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 25
[SF]::PostMessage($hw, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 900

[SF]::GetWindowRect($hw, [ref]$r) | Out-Null
"after dodge: $($r.Left),$($r.Top)-$($r.Right),$($r.Bottom)"

"--- log ---"
Get-Content $log | Where-Object { $_ -match 'snap: corners|flip: landed' } | Select-Object -Last 6

# put it back and fix the saved position (the dodge wrote the flipped one)
$p = $orig.Split(',')
[SF]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3], 0x0014) | Out-Null
Start-Sleep -Milliseconds 400
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
(Get-Content $ini) -replace '^x=.*', "x=$($p[0])" -replace '^y=.*', "y=$($p[1])" | Set-Content $ini -Encoding ASCII
"restored to $orig and rewrote dock.ini x/y"
Get-Content $ini | Select-String '^x=|^y='
