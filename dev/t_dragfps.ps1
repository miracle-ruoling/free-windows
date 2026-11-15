# Measure how often a window's position really updates while it is being dragged.
#
# Why this exists: "dragging the tray bar feels like 30 fps" is a claim about the *number of
# distinct positions per second*, which is measurable from the outside. Injected one step per
# sample, and a separate sampler thread polls GetWindowRect at ~1 kHz, so the report is a
# property of the dock, not of the injector. Run it against the tray bar and against the strip
# to A/B them.
#
#   .\t_dragfps.ps1                      # tray bar, 600 px right over 2 s
#   .\t_dragfps.ps1 -Target strip -Dx 0 -Dy 300
#   .\t_dragfps.ps1 -StepsPerSec 300     # press the injector harder
param(
    [ValidateSet('traybar', 'strip')] [string]$Target = 'traybar',
    [int]$Dx = 600, [int]$Dy = 0,
    [int]$Ms = 2000,
    [int]$StepsPerSec = 144,
    [int]$GrabX = 46
)
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class DragFps {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetCapture();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gi);
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public uint cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture,
      hwndMenuOwner, hwndMoveSize, hwndCaret;
    public RECT rcCaret;
  }
  // GetCapture() only answers for the calling thread, so ask the other thread's GUI state.
  public static IntPtr ThreadCapture(IntPtr h) {
    uint tid = GetWindowThreadProcessId(h, IntPtr.Zero);
    GUITHREADINFO gi = new GUITHREADINFO();
    gi.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
    if (tid == 0 || !GetGUIThreadInfo(tid, ref gi)) return IntPtr.Zero;
    return gi.hwndCapture;
  }
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }

  class Sample { public double T; public int Wx, Wy, Cx, Cy; }

  public static string Run(IntPtr h, int dx, int dy, int ms, int stepsPerSec, int grabX,
                           IntPtr strip) {
    RECT r0; GetWindowRect(h, out r0);
    int w = r0.Right - r0.Left, ht = r0.Bottom - r0.Top;
    int gx = r0.Left + grabX, gy = r0.Top + ht / 2;
    // The companion is only on screen while the pointer is on the strip (or in the group),
    // and a hidden layered window swallows nothing: park on the strip first, wait for the
    // fade, and only then go to the companion - otherwise the press lands on the desktop.
    string warm = "no strip";
    if (strip != IntPtr.Zero) {
      RECT s; GetWindowRect(strip, out s);
      SetCursorPos((s.Left + s.Right) / 2, (s.Top + s.Bottom) / 2);
      Thread.Sleep(400);
      warm = "strip centre";
    }
    SetCursorPos(gx, gy);
    Thread.Sleep(250);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);   // left down
    Thread.Sleep(80);
    bool grabbed = ThreadCapture(h) == h;
    if (!grabbed) {
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      return "press did not land on " + h + " (thread capture " + ThreadCapture(h) +
             ", warmup " + warm + "): window is probably hidden, nothing was dragged";
    }

    var samples = new List<Sample>(1 << 16);
    var stop = new ManualResetEventSlim(false);
    var sw = Stopwatch.StartNew();

    var sampler = new Thread(delegate() {
      while (!stop.IsSet) {
        Sample s = new Sample();
        s.T = sw.Elapsed.TotalMilliseconds;
        RECT r; GetWindowRect(h, out r);
        s.Wx = r.Left; s.Wy = r.Top;
        POINT p; GetCursorPos(out p);
        s.Cx = p.X; s.Cy = p.Y;
        samples.Add(s);
        Thread.SpinWait(400);
      }
    });
    sampler.IsBackground = true;
    sampler.Start();

    double stepMs = 1000.0 / (stepsPerSec > 0 ? stepsPerSec : 144);
    int steps = (int)(ms / stepMs);
    double next = sw.Elapsed.TotalMilliseconds;
    for (int i = 1; i <= steps; i++) {
      double target = i * stepMs;
      while (sw.Elapsed.TotalMilliseconds < target) Thread.SpinWait(60);
      SetCursorPos(gx + (int)((long)dx * i / steps), gy + (int)((long)dy * i / steps));
    }
    double endT = sw.Elapsed.TotalMilliseconds;
    Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);   // left up
    Thread.Sleep(120);
    stop.Set();
    sampler.Join(500);

    // position changes and their intervals
    var intervals = new List<double>();
    int changes = 0, distinct = 0, lastX = int.MinValue, lastY = int.MinValue;
    double lastT = -1, maxGap = 0, maxGapAt = 0;
    int maxLag = 0, minLag = int.MaxValue;
    int samplesInWindow = 0;
    foreach (Sample s in samples) {
      if (s.T > endT + 60) break;                   // ignore the tail after the release
      if (s.T < 100) continue;                      // ignore the press settling
      samplesInWindow++;
      if (s.Wx != lastX || s.Wy != lastY) {
        if (lastX != int.MinValue) {
          int ddx = s.Wx - lastX, ddy = s.Wy - lastY;
          if (ddx * ddx + ddy * ddy > 0) distinct++;
        }
        changes++;
        if (lastT >= 0) {
          double gap = s.T - lastT;
          intervals.Add(gap);
          if (gap > maxGap) { maxGap = gap; maxGapAt = s.T; }
        }
        lastT = s.T;
        lastX = s.Wx; lastY = s.Wy;
      }
      // how far the window is from where the grab offset says it should be
      int lag = s.Cx - (gx - r0.Left) - s.Wx;
      if (lag < minLag) minLag = lag;
      if (lag > maxLag) maxLag = lag;
    }
    intervals.Sort();
    double sum = 0; foreach (double v in intervals) sum += v;
    double median = intervals.Count > 0 ? intervals[intervals.Count / 2] : 0;
    double p95 = intervals.Count > 0 ? intervals[(int)(intervals.Count * 0.95)] : 0;
    double span = Math.Max(1, endT - 100);

    var sb = new StringBuilder();
    sb.AppendFormat("target window {0} rect {1},{2} {3}x{4}\n", h, r0.Left, r0.Top, w, ht);
    sb.AppendFormat("injected {0} steps over {1:F0} ms ({2} steps/s requested)\n",
                    steps, endT, stepsPerSec);
    sb.AppendFormat("sampler: {0} samples in the window ({1:F0}/s)\n",
                    samplesInWindow, samplesInWindow * 1000.0 / span);
    sb.AppendFormat("position updates: {0} ({1:F1}/s), median interval {2:F1} ms, p95 {3:F1} ms, max {4:F1} ms (at {5:F0} ms)\n",
                    changes, changes * 1000.0 / span, median, p95, maxGap, maxGapAt);
    sb.AppendFormat("lag (window behind cursor): {0}..{1} px\n", minLag == int.MaxValue ? 0 : minLag, maxLag);
    sb.AppendFormat("capture after release: {0}\n",
                    ThreadCapture(h) == IntPtr.Zero ? "none" : "still held");
    return sb.ToString();
  }
}
"@
[void][DragFps]::SetProcessDpiAwarenessContext([IntPtr](-4))
$cls = if ($Target -eq 'traybar') { 'DockTrayBarWindow' } else { 'DockStripWindow' }
$h = [DragFps]::Find($cls)
if ($h -eq [IntPtr]::Zero) { Write-Output "no $cls window"; exit 1 }
$grabX = if ($Target -eq 'traybar') { $GrabX } else { 40 }
# warm-up target: the strip (it is what makes the companions fade in)
$strip = if ($Target -eq 'traybar') { [DragFps]::Find('DockStripWindow') } else { [IntPtr]::Zero }
Write-Output ([DragFps]::Run($h, $Dx, $Dy, $Ms, $StepsPerSec, $grabX, $strip))
