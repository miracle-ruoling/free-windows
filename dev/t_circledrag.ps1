# Drag the whole group in FAST circles (the user's "非常快地画圈" stutter report).
#
#   .\t_circledrag.ps1 -Radius 60 -Turns 6 -StepMs 6 -RadPerStep 0.3
#
# The whole loop runs inside C#: a PowerShell loop with Start-Sleep cannot deliver 6 ms steps
# (measured 35 ms per step), and this test is about speed.
#
# Two things learned the hard way:
#   * SetCursorPos moves the cursor but injects no input, so the dock's low-level hook never sees
#     it and the drag does not follow - absolute mouse_event does inject.
#   * GetCapture() only reports a capture owned by the *calling* thread, so it always says 0 for
#     another process. Do not use it to test whether a press landed.
# A full number of turns comes back to the starting point, so the group ends where it began.
param(
    [int]$Radius = 60,
    [int]$Turns = 6,
    [int]$StepMs = 6,
    [double]$RadPerStep = 0.3,
    [int]$Inset = 6
)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public class CR {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static IntPtr Find(string cls, bool visibleOnly) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) {
        RECT r; GetWindowRect(h, out r);
        if (!visibleOnly || (IsWindowVisible(h) && r.Right - r.Left > 20)) { found = h; return false; }
      }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static string R(IntPtr h) { RECT r; GetWindowRect(h, out r);
    return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top); }

  public static void MoveAbs(int x, int y) {
    int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
    mouse_event(0x8001, (int)((long)x * 65535 / (w - 1)), (int)((long)y * 65535 / (h - 1)),
                0, UIntPtr.Zero);
  }

  // Grab at (gx,gy), run turns circles of radius around it, release. Samples how far the strip
  // trails the pointer.
  public static string Circle(IntPtr strip, int gx, int gy, int radius, int turns, int stepMs,
                              double radPerStep) {
    RECT s0; GetWindowRect(strip, out s0);
    int grabDx = s0.Left - gx, grabDy = s0.Top - gy;
    MoveAbs(gx, gy); Thread.Sleep(300);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);      // LEFTDOWN
    Thread.Sleep(60);
    int steps = (int)(2 * Math.PI / radPerStep * turns);
    double angle = 0; int maxLag = 0, lagSum = 0, samples = 0;
    var sw = Stopwatch.StartNew();
    for (int i = 0; i < steps; i++) {
      angle += radPerStep;
      int tx = gx + (int)(radius * Math.Cos(angle));
      int ty = gy + (int)(radius * Math.Sin(angle));
      MoveAbs(tx, ty);
      Thread.Sleep(stepMs);
      if (i % 3 == 0) {
        RECT r; GetWindowRect(strip, out r);
        int lag = Math.Max(Math.Abs(r.Left - (tx + grabDx)), Math.Abs(r.Top - (ty + grabDy)));
        if (lag > maxLag) maxLag = lag;
        lagSum += lag; samples++;
      }
    }
    sw.Stop();
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);      // LEFTUP
    Thread.Sleep(300);
    return string.Format("circled {0} steps in {1:N2}s ({2:N1} ms/step, {3} px radius, {4} turns)\n"
                       + "lag: worst {5} px, average {6:N1} px ({7} samples)",
                         steps, sw.Elapsed.TotalSeconds, sw.Elapsed.TotalMilliseconds / steps,
                         radius, turns, maxLag, samples > 0 ? (double)lagSum / samples : 0, samples);
  }
}
'@
[void][CR]::SetProcessDpiAwarenessContext([IntPtr](-4))

$strip = [CR]::Find('DockStripWindow', $false)
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no strip'; exit 1 }
$s = New-Object CR+RECT; [void][CR]::GetWindowRect($strip, [ref]$s)
# park the pointer on the strip first: the frame only exists while the pointer is at the group
[CR]::MoveAbs(($s.Left + $s.Right) / 2, ($s.Top + $s.Bottom) / 2)
Start-Sleep -Milliseconds 700
$box = [CR]::Find('DockGroupBoxWindow', $true)
if ($box -eq [IntPtr]::Zero) { Write-Output 'no visible group frame'; exit 1 }
$b = New-Object CR+RECT; [void][CR]::GetWindowRect($box, [ref]$b)
[void][CR]::GetWindowRect($strip, [ref]$s)
$gx = $b.Left + $Inset
$gy = [int](($b.Top + $b.Bottom) / 2)
$p = New-Object CR+POINT; $p.X = $gx; $p.Y = $gy
Write-Output ("strip " + [CR]::R($strip) + "  frame " + [CR]::R($box) + "  grab " + $gx + "," + $gy +
              " -> " + [CR]::WindowFromPoint($p).ToInt64())
$was = [CR]::R($strip)
Write-Output ([CR]::Circle($strip, $gx, $gy, $Radius, $Turns, $StepMs, $RadPerStep))
Write-Output ("strip now " + [CR]::R($strip) + "  (was " + $was + ")")
