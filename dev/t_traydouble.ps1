# H1.2 probe: click the grid cell of a tray app and report whether the double-click path
# fired (the dock logs "left x2 click" + a second "click up" for apps it sends twice).
#
# The cell is found from the dock's own log lines
#   tray: cell N (rR,cC) '<tip>' (<exe>) twice=1
# and the grid rect from
#   grid: WxH at X,Y
# so the probe never guesses coordinates.
#   -Exe     traytest.exe   which entry to click (matched against "twice=1" cells)
#   -Window  TrayTestWindow class of the window to check afterwards (optional)
param(
    [string]$Exe = "traytest.exe",
    [string]$Window = "TrayTestWindow"
)
Add-Type -ReferencedAssemblies System.Drawing -Language CSharp @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class TD {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public delegate bool EnumProc(IntPtr h, IntPtr lp);

  // FindWindow() is subject to UIPI and does not see the dock's windows from here;
  // EnumWindows does.
  public static IntPtr ByClass(string cls, bool visibleOnly) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() != cls) return true;
      if (visibleOnly && !IsWindowVisible(h)) return true;
      found = h;
      return false; }, IntPtr.Zero);
    return found;
  }
  public static void Click(int x, int y) { SetCursorPos(x,y); System.Threading.Thread.Sleep(220); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(80); mouse_event(0x0004,0,0,0,UIntPtr.Zero); }
  public static bool GridVisible() { return ByClass("DockGridWindow", true) != IntPtr.Zero; }
  public static string State(string cls) {
    IntPtr h = ByClass(cls, false);
    if (h == IntPtr.Zero) return "(no window of class " + cls + ")";
    RECT r; GetWindowRect(h, out r);
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
    return "vis=" + IsWindowVisible(h) + " rect=" + r.Left + "," + r.Top + " " + (r.Right-r.Left) + "x" + (r.Bottom-r.Top) + " txt='" + t + "'";
  }
}
'@
[void][TD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'

function GridRect {
    $line = Get-Content $log -Tail 4000 | Select-String -Pattern 'grid: \d+x\d+ at \d+,\d+' | Select-Object -Last 1
    if (-not $line) { return $null }
    [void]($line.Line -match 'grid: (\d+)x(\d+) at (\d+),(\d+)')
    return @([int]$Matches[3], [int]$Matches[4])
}
function FindCell([string]$exe) {
    $esc = [regex]::Escape($exe)
    $line = Get-Content $log -Tail 4000 |
            Select-String -Pattern "\(r(\d+),c(\d+)\).*$esc.*twice=1" | Select-Object -Last 1
    if (-not $line) { return $null }
    if ($line.Line -match '\(r(\d+),c(\d+)\)') { return @([int]$Matches[1], [int]$Matches[2]) }
    return $null
}
function ChevronPoint {
    $strip = [TD]::ByClass("DockStripWindow", $true)
    if ($strip -eq [IntPtr]::Zero) { Write-Host "  (strip window not found)"; return $null }
    $r = New-Object TD+RECT
    [void][TD]::GetWindowRect($strip, [ref]$r)
    $line = Get-Content $log -Tail 4000 | Select-String -Pattern 'layout: ' | Select-Object -Last 1
    if (-not $line -or $line.Line -notmatch 'chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)') {
        Write-Host "  (no chevron= in the last layout line)"; return $null
    }
    $cx = $r.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $cy = $r.Top + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    Write-Host ("  strip=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top) + " chevron -> " + $cx + "," + $cy)
    return @($cx, $cy)
}

Write-Output ("target window before: " + [TD]::State($Window))
if (-not [TD]::GridVisible()) {
    for ($i = 0; $i -lt 6; $i++) {
        $ch = ChevronPoint
        if (-not $ch) { break }
        [void][TD]::SetCursorPos($ch[0], $ch[1]); Start-Sleep -Milliseconds 250
        [void][TD]::SetCursorPos($ch[0] + 6, $ch[1] + 4); Start-Sleep -Milliseconds 250
        if ([TD]::GridVisible()) { break }
        [TD]::Click($ch[0], $ch[1]); Start-Sleep -Milliseconds 900
    }
}
if (-not [TD]::GridVisible()) { Write-Output "grid did not open"; exit 1 }
Start-Sleep -Milliseconds 300

$cell = FindCell $Exe
if (-not $cell) { Write-Output ("no 'twice=1' cell matches -Exe " + $Exe + " in the log"); exit 1 }
$origin = GridRect
if (-not $origin) { Write-Output "cannot read the grid rect from the log"; exit 1 }
$x = $origin[0] + 14 + $cell[1] * 66 + 30      # pad 14, 60 px cells, 6 px gaps
$y = $origin[1] + 14 + $cell[0] * 66 + 30
Write-Output ("grid at " + $origin[0] + "," + $origin[1] + " -> cell (r" + $cell[0] + ",c" + $cell[1] + ") at " + $x + "," + $y)
[TD]::Click($x, $y)
Start-Sleep -Milliseconds 1500
Write-Output ("target window after:  " + [TD]::State($Window))
Write-Output '--- log ---'
Get-Content $log -Tail 40 | Select-String 'tray:|grid:' | Select-Object -Last 14 | ForEach-Object { $_.Line }
