# Grid placement check: open the panel from the "^" button (posted click, no real
# cursor movement inside the strip) and report where it landed relative to the strip,
# the chevron and the work area.
#
#   -Tmp "x,y,w,h"  temporarily move/resize the strip for the test (restored at the end),
#                   used for "strip near the bottom edge" and "vertical strip" cases.
#
# The strip is wide and the content is centred, so the chevron sits at
#   start + items * (icon + gap),  start = pad + (W - 2*pad - total) / 2
# with icon = min(H - 2*pad, maxIcon) along the strip.  The cursor is parked in the
# top-left corner first so no slot is magnified while we measure.
param([string]$Tmp = "")

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public struct POINT { public int X; public int Y; }
public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

public class G {
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

[G]::SetProcessDPIAware() | Out-Null
$strip = [G]::Find('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'

$old = New-Object POINT
[G]::GetCursorPos([ref]$old) | Out-Null
[G]::SetCursorPos(8, 8) | Out-Null      # park the cursor away: no slot gets magnified

$r = New-Object RECT
[G]::GetWindowRect($strip, [ref]$r) | Out-Null
$orig = "$($r.Left),$($r.Top),$($r.Right - $r.Left),$($r.Bottom - $r.Top)"

if ($Tmp -ne "") {
    $p = $Tmp.Split(',')
    $tx = [int]$p[0]; $ty = [int]$p[1]; $tw = [int]$p[2]; $th = [int]$p[3]
    [G]::SetWindowPos($strip, [IntPtr]0, $tx, $ty, $tw, $th, 0x0014) | Out-Null   # NOZORDER|NOACTIVATE
    Start-Sleep -Milliseconds 400
    [G]::GetWindowRect($strip, [ref]$r) | Out-Null
    "moved strip to $Tmp (was $orig)"
}

Start-Sleep -Milliseconds 300
[G]::GetWindowRect($strip, [ref]$r) | Out-Null
$W = $r.Right - $r.Left
$H = $r.Bottom - $r.Top

$items = 15
$line = (Get-Content $log | Where-Object { $_ -match 'iconcache px=\d+ items=\d+' } | Select-Object -Last 1)
if ($line -and $line -match 'items=(\d+)') { $items = [int]$Matches[1] }

$pad = 10; $gap = 6
$icon = [Math]::Min([Math]::Max([Math]::Min($W, $H) - 2 * $pad, 18), 72)
$cell = $icon + $gap
$vertical = $H -gt $W
if ($vertical) { $long = $H } else { $long = $W }
# mirror ComputeButtons: capacity decides how many items are visible, the chevron is
# always the last cell and is the only one left when the strip overflows
$cap = [int][Math]::Floor(($long - 2 * $pad + $gap) / $cell)
if ($cap -lt 1) { $cap = 1 }
$needExpand = $cap -gt 1
$show = if ($needExpand) { $cap - 1 } else { $cap }
$visible = [Math]::Min($items, $show)
$cells = $visible + $(if ($needExpand) { 1 } else { 0 })
$total = $cells * $cell - $gap
$start = $pad + [int](($long - 2 * $pad - $total) / 2)
$chevStart = $start + $visible * $cell
$chevEnd = $chevStart + $icon
if ($vertical) { $cx = [int]($W / 2); $cy = $chevStart + [int]($icon / 2) }
else           { $cx = $chevStart + [int]($icon / 2); $cy = [int]($H / 2) }

$mon = [G]::MonitorFromWindow($strip, 2)
$mi = New-Object MONITORINFO
$mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
[G]::GetMonitorInfo($mon, [ref]$mi) | Out-Null
$wa = $mi.rcWork

"strip : $($r.Left),$($r.Top)-$($r.Right),$($r.Bottom) (${W}x${H}) items=$items vertical=$vertical"
"chevron (client, along the long axis): $chevStart..$chevEnd  -> click at $cx,$cy"
"work  : $($wa.Left),$($wa.Top)-$($wa.Right),$($wa.Bottom)"

$lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
[G]::PostMessage($strip, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 40
[G]::PostMessage($strip, 0x0202, [IntPtr]0, $lp) | Out-Null
Start-Sleep -Milliseconds 500

$grid = [G]::Find('DockGridWindow')
if ($grid -ne [IntPtr]::Zero) {
    $g = New-Object RECT
    [G]::GetWindowRect($grid, [ref]$g) | Out-Null
    "panel : $($g.Left),$($g.Top)-$($g.Right),$($g.Bottom) ($($g.Right - $g.Left)x$($g.Bottom - $g.Top))"
    $inside = ($g.Left -ge $wa.Left) -and ($g.Top -ge $wa.Top) -and
              ($g.Right -le $wa.Right) -and ($g.Bottom -le $wa.Bottom)
    $overlap = -not (($g.Right -le $r.Left) -or ($g.Left -ge $r.Right) -or
                     ($g.Bottom -le $r.Top) -or ($g.Top -ge $r.Bottom))
    "fully inside work area : $inside"
    "overlaps the strip     : $overlap"
    if ($vertical) {
        "side  : panel left = $($g.Left), strip right = $($r.Right)  (want strip.right+8 = $($r.Right + 8))"
        "anchor: panel bottom = $($g.Bottom), chevron bottom = $($r.Top + $chevEnd)"
    } else {
        "side  : panel top = $($g.Top), strip bottom = $($r.Bottom)  (want strip.bottom+8 = $($r.Bottom + 8), or above)"
        "anchor: panel right = $($g.Right), chevron right = $($r.Left + $chevEnd)"
    }
    # close it again
    [G]::PostMessage($strip, 0x0201, [IntPtr]1, $lp) | Out-Null
    Start-Sleep -Milliseconds 40
    [G]::PostMessage($strip, 0x0202, [IntPtr]0, $lp) | Out-Null
    Start-Sleep -Milliseconds 300
} else {
    'no DockGridWindow - the click missed "^"'
}

"--- log ---"
Get-Content $log | Where-Object { $_ -match 'grid: place|grid: \d+x\d+ at' } | Select-Object -Last 2

if ($Tmp -ne "") {
    $p = $orig.Split(',')
    [G]::SetWindowPos($strip, [IntPtr]0, [int]$p[0], [int]$p[1], [int]$p[2], [int]$p[3], 0x0014) | Out-Null
    Start-Sleep -Milliseconds 300
    'strip restored'
}
[G]::SetCursorPos($old.X, $old.Y) | Out-Null
