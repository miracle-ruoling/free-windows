# Does a FAST group scale drag make the group fade out? (bug report 2026-11-16 00:44)
#
# While the frame edge is dragged the box rect always trails the pointer by up to one message,
# so at 3000-4000 px/s the pointer can be outside the frame when CompanionVisibilityTick()
# samples it. If the visibility rule does not know "a scale is in progress", it reads that as
# "the pointer left the group" and fades the companion (and the frame) out mid-drag.
#
# Samples IsWindowVisible(companion) / (frame) ~2k times/s during the drag and reports the
# hidden ratio; a correct implementation keeps them visible for the whole drag.
#
#   .\t_groupscale_fast.ps1 [-Dx 700] [-Ms 250]
param([int]$Dx = 700, [int]$Ms = 250, [int]$Steps = 40)
Add-Type -Language CSharp @"
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class GSF {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gi);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public uint cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture,
      hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret;
  }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static IntPtr ThreadCapture(IntPtr h) {
    uint tid = GetWindowThreadProcessId(h, IntPtr.Zero);
    GUITHREADINFO gi = new GUITHREADINFO();
    gi.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
    if (tid == 0 || !GetGUIThreadInfo(tid, ref gi)) return IntPtr.Zero;
    return gi.hwndCapture;
  }
  public static string Run(IntPtr strip, IntPtr comp, IntPtr box, int dx, int ms, int steps) {
    RECT s0; GetWindowRect(strip, out s0);
    SetCursorPos((s0.Left + s0.Right) / 2, (s0.Top + s0.Bottom) / 2);
    Thread.Sleep(600);
    RECT b0; GetWindowRect(box, out b0);
    if (!IsWindowVisible(box)) return "frame not visible - pointer not on the strip?";
    int gx = b0.Right - 4, gy = (b0.Top + b0.Bottom) / 2;
    SetCursorPos(gx, gy);
    Thread.Sleep(200);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(80);
    if (ThreadCapture(box) != box) {
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      return "press did not land on the frame";
    }

    int compHidden = 0, boxHidden = 0, samples = 0;
    var stop = new ManualResetEventSlim(false);
    var sampler = new Thread(delegate() {
      while (!stop.IsSet) {
        samples++;
        if (!IsWindowVisible(comp)) compHidden++;
        if (!IsWindowVisible(box)) boxHidden++;
        Thread.SpinWait(400);
      }
    });
    sampler.IsBackground = true;
    sampler.Start();

    double stepMs = (double)ms / steps;
    var sw = Stopwatch.StartNew();
    for (int i = 1; i <= steps; i++) {
      double target = i * stepMs;
      while (sw.Elapsed.TotalMilliseconds < target) Thread.SpinWait(50);
      SetCursorPos(gx + (int)((long)dx * i / steps), gy);
    }
    Thread.Sleep(150);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(250);
    stop.Set();
    sampler.Join(500);

    RECT b1, s1; GetWindowRect(box, out b1); GetWindowRect(strip, out s1);
    double pps = dx * 1000.0 / ms;
    var sb = new StringBuilder();
    sb.AppendFormat("drag {0} px in {1} ms (~{2:F0} px/s)\n", dx, ms, pps);
    sb.AppendFormat("samples {0}: companion hidden {1} ({2:F1}%), frame hidden {3} ({4:F1}%)\n",
                    samples, compHidden, samples > 0 ? 100.0 * compHidden / samples : 0,
                    boxHidden, samples > 0 ? 100.0 * boxHidden / samples : 0);
    sb.AppendFormat("frame width {0} -> {1} (the scale itself kept working)\n",
                    b0.Right - b0.Left, b1.Right - b1.Left);
    sb.AppendFormat("strip width {0} -> {1}\n", s0.Right - s0.Left, s1.Right - s1.Left);
    return sb.ToString();
  }
}
"@
[void][GSF]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [GSF]::Find('DockStripWindow'); $comp = [GSF]::Find('DockTrayBarWindow'); $box = [GSF]::Find('DockGroupBoxWindow')
if ($strip -eq [IntPtr]::Zero -or $comp -eq [IntPtr]::Zero -or $box -eq [IntPtr]::Zero) {
    Write-Output 'missing window'; exit 1
}
Write-Output ([GSF]::Run($strip, $comp, $box, $Dx, $Ms, $Steps))
