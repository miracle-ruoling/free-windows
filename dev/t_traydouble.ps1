# H1.2 probe: click the grid cell of the app listed in [tray] doubleClick and report whether
# the double-click path fired.
#
# It reads the dock's own log lines ("tray: cell N (rR,cC) '...' ... twice=1") to find the
# cell, opens the grid by clicking the chevron, clicks that cell, then prints the log lines
# that belong to the click plus the state of the target window.
#   -Exe  traytest.exe   which entry to look for (matched against the "twice=1" cells)
#   -Window TrayTestWindow  class of the window to check afterwards (optional)
param(
    [string]$Exe = "traytest.exe",
    [string]$Window = "TrayTestWindow"
)
Add-Type -ReferencedAssemblies System.Drawing -Language CSharp @'
using System; using System.Runtime.InteropServices; using System.Text;
public class TD {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Click(int x, int y) { SetCursorPos(x,y); System.Threading.Thread.Sleep(220); mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(80); mouse_event(0x0004,0,0,0,UIntPtr.Zero); }
  public static bool GridVisible() { return IsWindowVisible(FindWindow("DockGridWindow", null)); }
  public static string State(string cls) {
    IntPtr h = FindWindow(cls, null);
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
    $line = Get-Content $log -Tail 600 | Select-String -Pattern 'grid: \d+x\d+ at (\d+),(\d+)' |
            Select-Object -Last 1
    if (-not $line) { return $null }
    [void]($line.Line -match 'grid: (\d+)x(\d+) at (\d+),(\d+)')
    return @([int]$Matches[3], [int]$Matches[4], [int]$Matches[1], [int]$Matches[2])
}
function FindCell([string]$exe) {
    $line = Get-Content $log -Tail 600 | Select-String -Pattern "\(r(\d+),c(\d+)\).*\(([^)]*$([regex]::Escape($exe)))\) twice=1" |
            Select-Object -Last 1
    if (-not $line) { return $null }
    if ($line.Line -match '\(r(\d+),c(\d+)\)') { return @([int]$Matches[1], [int]$Matches[2]) }
    return $null
}

Write-Output ("target window before: " + [TD]::State($Window))
if (-not [TD]::GridVisible()) {
    for ($i = 0; $i -lt 5; $i++) {
        [void][TD]::SetCursorPos(1193, 53); Start-Sleep -Milliseconds 220
        [void][TD]::SetCursorPos(1200, 55); Start-Sleep -Milliseconds 220
        if ([TD]::GridVisible()) { break }
        [TD]::Click(1193, 53); Start-Sleep -Milliseconds 800
    }
}
if (-not [TD]::GridVisible()) { Write-Output "grid did not open"; exit 1 }
Start-Sleep -Milliseconds 300

$cell = FindCell $Exe
if (-not $cell) { Write-Output ("no cell in the log matches -Exe " + $Exe + " (is it in [tray] doubleClick?)"); exit 1 }
$rect = GridRect
if (-not $rect) { Write-Output "cannot read the grid rect from the log"; exit 1 }
# cells: pad 14, 60 px cells, 6 px gaps
$x = $rect[0] + 14 + $cell[1] * 66 + 30
$y = $rect[1] + 14 + $cell[0] * 66 + 30
Write-Output ("grid " + $rect[0] + "," + $rect[1] + " " + $rect[2] + "x" + $rect[3] + " -> cell (r" + $cell[0] + ",c" + $cell[1] + ") at " + $x + "," + $y)
[TD]::Click($x, $y)
Start-Sleep -Milliseconds 1500
Write-Output ("target window after:  " + [TD]::State($Window))
Write-Output '--- log ---'
Get-Content $log -Tail 40 | Select-String 'tray:|grid:' | Select-Object -Last 14 | ForEach-Object { $_.Line }
