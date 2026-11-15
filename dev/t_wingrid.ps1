# Open the grid from the "^" button using the geometry the dock now logs, and report
# where the panel landed. Replaces the old formula-based version (the row is no longer
# "cap-1 icons": the Windows button owns a cell too).
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WG2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
}
"@
[void][WG2]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [WG2]::Find('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output "no strip"; exit 1 }
$r = New-Object WG2+RECT
[void][WG2]::GetWindowRect($strip, [ref]$r)
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$line = Get-Content $log -Tail 300 | Where-Object { $_ -match 'layout: ' } | Select-Object -Last 1
if (-not $line) { Write-Output "no layout line"; exit 1 }
Write-Output ("log: " + $line.Trim())
if ($line -notmatch "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { Write-Output "parse failed"; exit 1 }
$cl = [int]$Matches[1]; $ct = [int]$Matches[2]; $cr = [int]$Matches[3]; $cb = [int]$Matches[4]
$cx = ($cl + $cr) / 2; $cy = ($ct + $cb) / 2
$old = New-Object WG2+POINT
[void][WG2]::GetCursorPos([ref]$old)
[void][WG2]::SetCursorPos(8, 8)          # no slot magnified while we click
Start-Sleep -Milliseconds 250
$lp = [IntPtr]([int64]($cy -shl 16) -bor $cx)
[void][WG2]::PostMessage($strip, 0x0201, [IntPtr]1, $lp)   # WM_LBUTTONDOWN, MK_LBUTTON
Start-Sleep -Milliseconds 60
[void][WG2]::PostMessage($strip, 0x0202, [IntPtr]0, $lp)   # WM_LBUTTONUP
Start-Sleep -Milliseconds 600
$grid = [WG2]::Find('DockGridWindow')
if ($grid -eq [IntPtr]::Zero) { Write-Output "no grid window"; exit 1 }
$g = New-Object WG2+RECT
[void][WG2]::GetWindowRect($grid, [ref]$g)
$mi = New-Object WG2+MONITORINFO
$mi.cbSize = 40
$mon = [WG2]::MonitorFromWindow($strip, 2)
[void][WG2]::GetMonitorInfo($mon, [ref]$mi)
Write-Output ("strip  " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
Write-Output ("chev   " + ($r.Left+$cl) + "," + ($r.Top+$ct) + " " + ($cr-$cl) + "x" + ($cb-$ct))
Write-Output ("grid   " + $g.Left + "," + $g.Top + " " + ($g.Right-$g.Left) + "x" + ($g.Bottom-$g.Top) + " visible=" + [WG2]::IsWindowVisible($grid))
Write-Output ("work   " + $mi.rcWork.Left + "," + $mi.rcWork.Top + "-" + $mi.rcWork.Right + "," + $mi.rcWork.Bottom)
$inside = ($g.Left -ge $mi.rcWork.Left) -and ($g.Top -ge $mi.rcWork.Top) -and ($g.Right -le $mi.rcWork.Right) -and ($g.Bottom -le $mi.rcWork.Bottom)
$overlap = -not (($g.Right -le $r.Left) -or ($g.Left -ge $r.Right) -or ($g.Bottom -le $r.Top) -or ($g.Top -ge $r.Bottom))
Write-Output ("inside work area=" + $inside + "  overlaps strip=" + $overlap)
if (-not $KeepOpen) {
    $lp2 = [IntPtr]([int64]($cy -shl 16) -bor $cx)
    [void][WG2]::PostMessage($strip, 0x0201, [IntPtr]1, $lp2)
    Start-Sleep -Milliseconds 60
    [void][WG2]::PostMessage($strip, 0x0202, [IntPtr]0, $lp2)
    Write-Output "closed the grid again"
}
[void][WG2]::SetCursorPos($old.X, $old.Y)
