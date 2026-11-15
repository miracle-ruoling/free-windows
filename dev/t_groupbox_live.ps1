# R2 probe: does the frame follow a member that is being dragged *live* (not only on release)?
#
# Drags the tray bar with a real mouse while a sampler polls both rectangles ~200k times/s,
# and counts samples where the frame is not exactly (strip ∪ companion) + margin. A frame that
# is only recomputed on release shows up as a long run of mismatches; a live one only ever
# misses by the one frame the sampler catches mid-update.
#
#   .\t_groupbox_live.ps1 [-Dx 150] [-Dy 80] [-Margin 8]
param([int]$Dx = 150, [int]$Dy = 80, [int]$Margin = 8, [int]$Ms = 1200, [int]$StepsPerSec = 144)
Add-Type -Language CSharp @"
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class GBL {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  class S { public int SL, ST, SR, SB, CL, CT, CR, CB, BL, BT, BR, BB; }
  public static string Run(IntPtr strip, IntPtr comp, IntPtr box, int dx, int dy, int ms,
                           int stepsPerSec, int margin) {
    RECT c0; GetWindowRect(comp, out c0);
    RECT s0; GetWindowRect(strip, out s0);
    // warm the group up so the frame is on screen (it only shows while the pointer is on the strip)
    SetCursorPos((s0.Left + s0.Right) / 2, (s0.Top + s0.Bottom) / 2);
    Thread.Sleep(450);
    int gx = c0.Left + 46, gy = (c0.Top + c0.Bottom) / 2;   // first cell: drawn, so it takes the press
    SetCursorPos(gx, gy);
    Thread.Sleep(250);

    var samples = new System.Collections.Generic.List<S>(1 << 16);
    var stop = new ManualResetEventSlim(false);
    var sw = Stopwatch.StartNew();
    var sampler = new Thread(delegate() {
      while (!stop.IsSet) {
        S s = new S();
        RECT a, b, c;
        GetWindowRect(strip, out a); GetWindowRect(comp, out b); GetWindowRect(box, out c);
        s.SL = a.Left; s.ST = a.Top; s.SR = a.Right; s.SB = a.Bottom;
        s.CL = b.Left; s.CT = b.Top; s.CR = b.Right; s.CB = b.Bottom;
        s.BL = c.Left; s.BT = c.Top; s.BR = c.Right; s.BB = c.Bottom;
        samples.Add(s);
        Thread.SpinWait(300);
      }
    });
    sampler.IsBackground = true;
    sampler.Start();

    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(80);
    double stepMs = 1000.0 / (stepsPerSec > 0 ? stepsPerSec : 144);
    int steps = (int)(ms / stepMs);
    for (int i = 1; i <= steps; i++) {
      double target = i * stepMs;
      while (sw.Elapsed.TotalMilliseconds < target) Thread.SpinWait(60);
      SetCursorPos(gx + (int)((long)dx * i / steps), gy + (int)((long)dy * i / steps));
    }
    Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(200);
    stop.Set();
    sampler.Join(500);

    int bad = 0, total = 0, runs = 0;
    bool inBadRun = false;
    int maxLagPx = 0;
    foreach (S s in samples) {
      total++;
      int wl = Math.Min(s.SL, s.CL) - margin, wt = Math.Min(s.ST, s.CT) - margin;
      int wr = Math.Max(s.SR, s.CR) + margin, wb = Math.Max(s.SB, s.CB) + margin;
      int e = Math.Max(Math.Max(Math.Abs(s.BL - wl), Math.Abs(s.BT - wt)),
                       Math.Max(Math.Abs(s.BR - wr), Math.Abs(s.BB - wb)));
      if (e > maxLagPx) maxLagPx = e;
      if (e > 1) {
        bad++;
        if (!inBadRun) { runs++; inBadRun = true; }
      } else inBadRun = false;
    }
    RECT fe; GetWindowRect(box, out fe);
    return "companion dragged to " + (c0.Left) + "," + (c0.Top) + " +(" + dx + "," + dy + ")\n" +
           "samples off by >1 px: " + bad + " of " + total + " in " + runs + " run(s); worst " +
           maxLagPx + " px\n" +
           "frame at the end: " + fe.Left + "," + fe.Top + "-" + fe.Right + "," + fe.Bottom +
           " visible=" + IsWindowVisible(box) + "\n";
  }
}
"@
[void][GBL]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [GBL]::Find('DockStripWindow')
$comp = [GBL]::Find('DockTrayBarWindow')
$box = [GBL]::Find('DockGroupBoxWindow')
if ($strip -eq [IntPtr]::Zero -or $comp -eq [IntPtr]::Zero -or $box -eq [IntPtr]::Zero) {
    Write-Output 'missing window (strip / tray bar / frame)'; exit 1
}
Write-Output ([GBL]::Run($strip, $comp, $box, $Dx, $Dy, $Ms, $StepsPerSec, $Margin))
