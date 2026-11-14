# Quick-dodge check: post a double click on the strip's left padding (empty strip, not
# an icon) and report where the window landed plus the log lines it produced.
# Messages are posted straight to DockStripWindow - the real cursor is not moved.
# Note: if the user happens to be moving the mouse over the strip, a posted DOWN can be
# dropped by the "stale press" guard (a real WM_MOUSEMOVE arrives before our UP), so the
# pair is retried a few times and the run is judged from the log.
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public struct POINT { public int X; public int Y; }
public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

public class F {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
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

[F]::SetProcessDPIAware() | Out-Null      # otherwise every rect comes back scaled (125% here)
$h = [F]::Find('DockStripWindow')
if ($h -eq [IntPtr]::Zero) { 'no DockStripWindow found'; exit 1 }
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'

$r = New-Object RECT
[F]::GetWindowRect($h, [ref]$r) | Out-Null
$mon = [F]::MonitorFromWindow($h, 2)
$mi = New-Object MONITORINFO
$mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
[F]::GetMonitorInfo($mon, [ref]$mi) | Out-Null
$wa = $mi.rcWork

$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$origLeft = $r.Left
$origTop = $r.Top
$cx = 40                                              # left padding: left of the first icon
$cy = [int]($hh / 2)

"strip: $($r.Left),$($r.Top) - $($r.Right),$($r.Bottom)  (${w}x${hh})"
"work : $($wa.Left),$($wa.Top) - $($wa.Right),$($wa.Bottom)"
"click at client $cx,$cy"

$lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
function ClickPair {
    [F]::PostMessage($h, 0x0201, [IntPtr]1, $lp) | Out-Null   # WM_LBUTTONDOWN
    Start-Sleep -Milliseconds 25
    [F]::PostMessage($h, 0x0202, [IntPtr]0, $lp) | Out-Null   # WM_LBUTTONUP
}

for ($i = 0; $i -lt 4; $i++) {
    ClickPair
    Start-Sleep -Milliseconds 120
    ClickPair
    Start-Sleep -Milliseconds 650
    $hit = @(Get-Content $log -Tail 40 | Where-Object { $_ -match 'flip: double click' })
    if ($hit.Count -gt 0) { break }
    "attempt $($i + 1): no flip yet, retrying"
}

Start-Sleep -Milliseconds 400
[F]::GetWindowRect($h, [ref]$r) | Out-Null
"after dodge: $($r.Left),$($r.Top)"
$expectTop = $wa.Top + $wa.Bottom - $origTop - $hh
"expected: x=$origLeft (unchanged), y=$expectTop (mirrored across the work area centre)"

"--- log tail ---"
Get-Content $log -Tail 14
