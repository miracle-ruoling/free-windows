# Does the native taskbar come up during a fast "right -> left" cycle on the Windows cell?
#
#   -Mode right-only       one right click (Win+X) and nothing else
#   -Mode right-then-left  right click, wait -Gap ms, then a left click (Ctrl+Esc)
#   -Mode left-only        one left click (Ctrl+Esc)
#
# The taskbar window is only enumerable while it sits off screen, so the handles are
# collected up front and then polled: y ~1078 = hidden, y ~1020 = expanded.
param(
    [ValidateSet("right-only", "right-then-left", "left-only", "cycle")][string]$Mode = "right-then-left",
    [int]$Gap = 900,
    [int]$TotalMs = 2600,
    [int]$SampleMs = 10,
    [int]$Cycles = 4
)
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public class WT {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static List<IntPtr> Bars = new List<IntPtr>();

  public static void Collect() {
    Bars.Clear();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      string c = b.ToString();
      if (c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") Bars.Add(h);
      return true; }, IntPtr.Zero);
  }

  static void Click(uint down, uint up, int x, int y) {
    SetCursorPos(x, y);
    Thread.Sleep(15);
    mouse_event(down, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(40);
    mouse_event(up, 0, 0, 0, UIntPtr.Zero);
  }

  // returns a log of the bar state transitions
  public static string Run(string mode, int gap, int totalMs, int sampleMs, int cx, int cy, int cycles = 4) {
    Collect();
    var sb = new StringBuilder();
    sb.AppendLine("bars: " + Bars.Count);
    Thread t = null;
    if (mode != "none") {
      t = new Thread(delegate() {
        if (mode == "right-only") {
          Click(0x0008, 0x0010, cx, cy);
        } else if (mode == "left-only") {
          Click(0x0002, 0x0004, cx, cy);
        } else if (mode == "cycle") {
          for (int i = 0; i < cycles; i++) {
            Click(0x0008, 0x0010, cx, cy);
            Thread.Sleep(gap);
            Click(0x0002, 0x0004, cx, cy);
            Thread.Sleep(gap);
          }
        } else {
          Click(0x0008, 0x0010, cx, cy);
          Thread.Sleep(gap);
          Click(0x0002, 0x0004, cx, cy);
        }
      });
      t.IsBackground = true;
      t.Start();
    }
    var sw = Stopwatch.StartNew();
    string last = "";
    int lastY = -99999;
    while (sw.ElapsedMilliseconds < totalMs) {
      var parts = new List<string>();
      foreach (IntPtr h in Bars) {
        if (!IsWindow(h)) { parts.Add("gone"); continue; }
        RECT r; GetWindowRect(h, out r);
        int cloaked = 0; DwmGetWindowAttribute(h, 14, out cloaked, 4);   // DWMWA_CLOAKED
        parts.Add(string.Format("{0},{1} {2}x{3}{4}", r.Left, r.Top, r.Right - r.Left,
                                r.Bottom - r.Top,
                                (cloaked != 0 ? " cloaked" : "") + (IsWindowVisible(h) ? "" : " hidden")));
      }
      string cur = string.Join(" | ", parts.ToArray());
      int y = -99999;
      foreach (IntPtr h in Bars) { RECT r; if (GetWindowRect(h, out r)) { y = r.Top; break; } }
      if (cur != last || Math.Abs(y - lastY) > 1) {
        sb.AppendLine(string.Format("{0,6} ms  y={1,6}  {2}", sw.ElapsedMilliseconds, y, cur));
        last = cur; lastY = y;
      }
      Thread.Sleep(sampleMs);
    }
    if (t != null) t.Join();
    return sb.ToString();
  }
}
"@
[void][WT]::SetProcessDpiAwarenessContext([IntPtr](-4))

# strip + the win cell (client rect from the last "layout:" line)
$strip = [IntPtr]::Zero
[void][WT]::Collect()
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FS {
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
    return found;
  }
}
"@
$strip = [FS]::Find("DockStripWindow")
$r = New-Object FS+RECT
if ($strip -eq [IntPtr]::Zero -or -not [FS]::GetWindowRect($strip, [ref]$r)) {
    Write-Output "strip not found"; exit 1
}
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$line = Get-Content $log -Tail 600 | Select-String -Pattern "layout: " | Select-Object -Last 1
if (-not $line -or $line.Line -notmatch "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") {
    Write-Output "cannot read the win cell from the layout log"; exit 1
}
$cx = $r.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = $r.Top + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("strip=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top) +
              "  win cell -> screen " + $cx + "," + $cy)
$save = New-Object WT+POINT
[void][WT]::GetCursorPos([ref]$save)

Write-Output ("=== mode=" + $Mode + " gap=" + $Gap + " cycles=" + $Cycles + " ===")
Write-Output ([WT]::Run($Mode, $Gap, $TotalMs, $SampleMs, $cx, $cy, $Cycles))

[void][WT]::SetCursorPos($save.X, $save.Y)
[WT]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
[WT]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
Write-Output "--- dock log (last 20 win button / retry lines) ---"
Get-Content $log -Tail 200 | Select-String -Pattern "win button|tray:|falling back" | Select-Object -Last 20 |
    ForEach-Object { $_.Line }
