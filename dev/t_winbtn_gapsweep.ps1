# Sweep the "right click -> left click" gap and report (a) whether the native taskbar
# rises and (b) what the foreground window class was, so we can tell whether Start
# actually opened.
param([int[]]$Gaps = @(120, 200, 300, 450, 700, 1000), [int]$Watch = 2200)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;
using System.Text; using System.Threading;
public class SW {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static string Cls(IntPtr h) { StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200); return b.ToString(); }
  public static IntPtr Bar() { return FindWindow("Shell_TrayWnd", null); }
  public static int BarY() { IntPtr h = Bar(); if (h == IntPtr.Zero) return -99999; RECT r; if (!GetWindowRect(h, out r)) return -99999; return r.Top; }
  public static void Click(uint down, uint up, int x, int y) {
    SetCursorPos(x, y); Thread.Sleep(20);
    mouse_event(down, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(35);
    mouse_event(up, 0, 0, 0, UIntPtr.Zero); }
  public static void Tap(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); Thread.Sleep(50); keybd_event(vk, 0, 2, UIntPtr.Zero); }

  // one "right, gap, left" round: returns "minY maxY firstRiseMs fgAfterRight fgAfterLeft"
  public static string Round(int gap, int watch, int cx, int cy) {
    int y0 = BarY();
    int minY = 99999, maxY = -99999, firstRise = -1;
    var sw = Stopwatch.StartNew();
    var t = new Thread(delegate() {
      Click(0x0008, 0x0010, cx, cy);
      Thread.Sleep(gap);
      Click(0x0002, 0x0004, cx, cy);
    });
    t.IsBackground = true; t.Start();
    while (sw.ElapsedMilliseconds < watch) {
      int y = BarY();
      if (y > -90000) { if (y < minY) minY = y; if (y > maxY) maxY = y; if (firstRise < 0 && y < y0 - 4) firstRise = (int)sw.ElapsedMilliseconds; }
      Thread.Sleep(6);
    }
    t.Join();
    string fg = Cls(GetForegroundWindow());
    return string.Format("y0={0} min={1} max={2} riseAt={3}ms fg='{4}' finalY={5}",
        y0, minY, maxY, firstRise, fg, BarY());
  }
}
"@
[void][SW]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class FS3 {
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
$strip = [FS3]::Find("DockStripWindow")
$sr = New-Object FS3+RECT
[void][FS3]::GetWindowRect($strip, [ref]$sr)
$line = Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 600 |
        Select-String -Pattern "layout: " | Select-Object -Last 1
$line.Line -match "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = $sr.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = $sr.Top + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("win cell -> " + $cx + "," + $cy + "   (bar hidden is y~1078, expanded y~1020)")

foreach ($g in $Gaps) {
    [SW]::Tap(0x1B); Start-Sleep -Milliseconds 250      # close whatever is open
    Write-Output ("gap " + $g + " ms : " + [SW]::Round($g, $Watch, $cx, $cy))
    Start-Sleep -Milliseconds 400
}
[SW]::Tap(0x1B)
Write-Output "--- dock log tail ---"
Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 120 |
    Select-String -Pattern "win button|still on screen" | Select-Object -Last 25 | ForEach-Object { $_.Line }
