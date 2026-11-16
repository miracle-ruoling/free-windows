# Is the taskbar mod's "expansion permission" still live after a Win+X press?
#
#   hover the bottom edge  -> the mod blocks the shell's unhide, so the bar stays down
#   right click the Windows cell (Win+X) and hover again -> if the bar slides up, the
#   permission that the Win press created was never revoked (the "latched permission" bug).
#
#   -Mode baseline | after-winx | after-left | after-left-latched
param([ValidateSet("baseline", "after-winx", "after-left", "after-left-latched")][string]$Mode = "baseline",
      [int]$Wait = 1200, [int]$Watch = 1800)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;
using System.Text; using System.Threading;
public class HP {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static string BarState() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) {
      // expanded bars are not enumerable by class in this build; fall back to the
      // remembered handle search
      return "FindWindow failed";
    }
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " (" + r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top) + ") cloaked=" + cl;
  }
  public static void Click(uint down, uint up, int x, int y) {
    SetCursorPos(x, y); Thread.Sleep(20);
    mouse_event(down, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(40);
    mouse_event(up, 0, 0, 0, UIntPtr.Zero);
  }
  public static string Watch(int ms) {
    var sb = new StringBuilder();
    var sw = Stopwatch.StartNew();
    string last = ""; int lastY = -99999;
    while (sw.ElapsedMilliseconds < ms) {
      IntPtr h = FindWindow("Shell_TrayWnd", null);
      string cur = (h == IntPtr.Zero ? "none" : BarState());
      int y = -99998;
      if (h != IntPtr.Zero) { RECT r; if (GetWindowRect(h, out r)) y = r.Top; }
      if (cur != last || Math.Abs(y - lastY) > 1) { sb.AppendLine(sw.ElapsedMilliseconds + " ms  " + cur); last = cur; lastY = y; }
      Thread.Sleep(15);
    }
    return sb.ToString();
  }
}
"@
[void][HP]::SetProcessDpiAwarenessContext([IntPtr](-4))
$bottom = [HP]::GetSystemMetrics(1)
Write-Output ("screen 1920x" + $bottom + "   start: " + [HP]::BarState())

function Probe([string]$tag) {
    Write-Output ("--- " + $tag + " : hover the bottom edge ---")
    [void][HP]::SetCursorPos(900, $bottom - 3)
    Start-Sleep -Milliseconds 100
    [void][HP]::SetCursorPos(900, $bottom - 1)
    Write-Output ([HP]::Watch($Wait))
    [void][HP]::SetCursorPos(900, $bottom - 300)
    Start-Sleep -Milliseconds 300
    Write-Output ("after: " + [HP]::BarState())
}

# strip win cell (screen point) from the dock log + strip rect
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class FS2 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found; }
}
"@
$strip = [FS2]::Find("DockStripWindow")
$sr = New-Object FS2+RECT
[void][FS2]::GetWindowRect($strip, [ref]$sr)
$line = Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 600 |
        Select-String -Pattern "layout: " | Select-Object -Last 1
$line.Line -match "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = $sr.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = $sr.Top + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("win cell -> " + $cx + "," + $cy)

switch ($Mode) {
    "baseline" { Probe "baseline (clean state)" }
    "after-winx" {
        [HP]::Click(0x0008, 0x0010, $cx, $cy);
        Start-Sleep -Milliseconds 400
        [void][HP]::SetCursorPos(900, $bottom - 300)
        Start-Sleep -Milliseconds 1200
        Probe "after Win+X (permission should be dead)"
    }
    "after-left" {
        [HP]::Click(0x0002, 0x0004, $cx, $cy);
        Start-Sleep -Milliseconds 400
        [void][HP]::SetCursorPos(900, $bottom - 300)
        Start-Sleep -Milliseconds 700
        Probe "after a left click (Start, never presses Win)"
    }
    "after-left-latched" {
        [HP]::Click(0x0008, 0x0010, $cx, $cy);
        Start-Sleep -Milliseconds 300
        Probe "hover, right after Win+X (permission latched)"
    }
}
Start-Sleep -Milliseconds 300
Write-Output "--- dock log tail ---"
Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 60 |
    Select-String -Pattern "win button|tray:|falling back" | Select-Object -Last 8 | ForEach-Object { $_.Line }

