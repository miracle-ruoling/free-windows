# Drag the strip and measure how fast the attached window follows it.
#
# The bug this exists for: dragging the strip itself is smooth (the strip is moved inside the
# frame tick, ~139 Hz), but the tray bar it drags along looked like ~30 fps. The sampler polls
# both windows' rectangles ~280k times/s, so the *ratio* between the two update rates is a
# property of the dock, not of the injector (same injected steps drive both).
#
#   .\t_followfps.ps1                 # drag via the chevron, 500 px right / 200 px down
#   .\t_followfps.ps1 -Dx -400 -Dy 0
param([int]$Dx = 500, [int]$Dy = 200, [int]$Ms = 1500, [int]$StepsPerSec = 144, [int]$Margin = 8)
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class FollowFps {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gi);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
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

  class S { public double T; public int Sx, Sy, Cx, Cy, Bx, By; }

  public static string Run(IntPtr strip, IntPtr comp, int dx, int dy, int ms, int stepsPerSec,
                           int grabX, int grabY, IntPtr box, int margin) {
    RECT s0; GetWindowRect(strip, out s0);
    RECT c0; GetWindowRect(comp, out c0);
    int off0x = c0.Left - s0.Left, off0y = c0.Top - s0.Top;
    int boff0x = 0, boff0y = 0;
    if (box != IntPtr.Zero) {
      RECT b0; GetWindowRect(box, out b0);
      boff0x = b0.Left - s0.Left; boff0y = b0.Top - s0.Top;
    }
    int gx = s0.Left + grabX, gy = s0.Top + grabY;
    SetCursorPos(gx, gy);
    Thread.Sleep(300);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(80);
    if (ThreadCapture(strip) != strip) {
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);   // never leave the button logically down
      return "press did not land on the strip (capture " + ThreadCapture(strip) + ")";
    }

    var list = new List<S>(1 << 17);
    var stop = new ManualResetEventSlim(false);
    var sw = Stopwatch.StartNew();
    var sampler = new Thread(delegate() {
      while (!stop.IsSet) {
        S s = new S();
        s.T = sw.Elapsed.TotalMilliseconds;
        RECT a, b, x; GetWindowRect(strip, out a); GetWindowRect(comp, out b);
        if (box != IntPtr.Zero) GetWindowRect(box, out x); else { x.Left = 0; x.Top = 0; }
        POINT p; GetCursorPos(out p);
        s.Sx = a.Left; s.Sy = a.Top; s.Cx = b.Left; s.Cy = b.Top;
        s.Bx = x.Left; s.By = x.Top;
        list.Add(s);
        Thread.SpinWait(300);
      }
    });
    sampler.IsBackground = true;
    sampler.Start();

    double stepMs = 1000.0 / (stepsPerSec > 0 ? stepsPerSec : 144);
    int steps = (int)(ms / stepMs);
    for (int i = 1; i <= steps; i++) {
      double target = i * stepMs;
      while (sw.Elapsed.TotalMilliseconds < target) Thread.SpinWait(60);
      SetCursorPos(gx + (int)((long)dx * i / steps), gy + (int)((long)dy * i / steps));
    }
    double endT = sw.Elapsed.TotalMilliseconds;
    Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(150);
    stop.Set();
    sampler.Join(500);

    // Put the strip back where the user had it: a measurement must not move his layout. This
    // is a plain second drag, so it goes through exactly the same code as the test itself.
    RECT sEnd; GetWindowRect(strip, out sEnd);
    string back = "not needed";
    if (sEnd.Left != s0.Left || sEnd.Top != s0.Top) {
      int bx = sEnd.Left + grabX, by = sEnd.Top + grabY;
      SetCursorPos(bx, by);
      Thread.Sleep(300);
      mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
      Thread.Sleep(60);
      SetCursorPos(bx + 6, by + 6);
      Thread.Sleep(60);
      int tx = bx + (s0.Left - sEnd.Left), ty = by + (s0.Top - sEnd.Top);
      for (int i = 1; i <= 20; i++)
        SetCursorPos(bx + 6 + (int)((long)(tx - bx - 6) * i / 20),
                     by + 6 + (int)((long)(ty - by - 6) * i / 20));
      Thread.Sleep(150);
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      Thread.Sleep(300);
      RECT br; GetWindowRect(strip, out br);
      back = br.Left + "," + br.Top;
    }

    var sInt = new List<double>(); var cInt = new List<double>(); var bInt = new List<double>();
    int sCh = 0, cCh = 0, bCh = 0;
    int lastSx = int.MinValue, lastSy = 0, lastCx = int.MinValue, lastCy = 0;
    int lastBx = int.MinValue, lastBy = 0;
    double lastST = -1, lastCT = -1, lastBT = -1, maxSGap = 0, maxCGap = 0, maxBGap = 0;
    int staleFrames = 0;            // strip moved, companion stayed (visible separation)
    bool countStale = false;        // off by default: the companion is moved *before* the strip
                                    // inside Present(), so a sampler running 100x faster than
                                    // the frame rate always sees the companion's change one
                                    // sample earlier - that is an artefact, not a bug.
    double sepSum = 0, sepMax = 0, bsepSum = 0, bsepMax = 0;
    int sepN = 0;
    foreach (S s in list) {
      if (s.T > endT) break;
      if (s.T < 100) continue;
      bool sMoved = s.Sx != lastSx || s.Sy != lastSy;
      if (sMoved) {
        if (lastST >= 0) { double g = s.T - lastST; sInt.Add(g); if (g > maxSGap) maxSGap = g; }
        lastST = s.T; sCh++; lastSx = s.Sx; lastSy = s.Sy;
      }
      bool cMoved = s.Cx != lastCx || s.Cy != lastCy;
      if (cMoved) {
        if (lastCT >= 0) { double g = s.T - lastCT; cInt.Add(g); if (g > maxCGap) maxCGap = g; }
        lastCT = s.T; cCh++; lastCx = s.Cx; lastCy = s.Cy;
      }
      if (box != IntPtr.Zero) {
        bool bMoved = s.Bx != lastBx || s.By != lastBy;
        if (bMoved) {
          if (lastBT >= 0) { double g = s.T - lastBT; bInt.Add(g); if (g > maxBGap) maxBGap = g; }
          lastBT = s.T; bCh++; lastBx = s.Bx; lastBy = s.By;
        }
        int bex = Math.Abs((s.Bx - s.Sx) - boff0x), bey = Math.Abs((s.By - s.Sy) - boff0y);
        double bsep = Math.Max(bex, bey);
        bsepSum += bsep;
        if (bsep > bsepMax) bsepMax = bsep;
      }
      if (countStale && sMoved && !cMoved) staleFrames++;
      // separation: how far the companion has slipped from its rest offset while both move
      int ex = Math.Abs((s.Cx - s.Sx) - off0x), ey = Math.Abs((s.Cy - s.Sy) - off0y);
      double sep = Math.Max(ex, ey);
      sepSum += sep; sepN++;
      if (sep > sepMax) sepMax = sep;
    }
    // drift: did the companion keep its offset relative to the strip?
    RECT en, ec; GetWindowRect(strip, out en); GetWindowRect(comp, out ec);
    int off1x = ec.Left - en.Left, off1y = ec.Top - en.Top;
    // and is the frame still exactly the members' bounding rect + margin?
    string boxGeom = "no frame";
    if (box != IntPtr.Zero) {
      RECT fr; GetWindowRect(box, out fr);
      int wantL = Math.Min(en.Left, ec.Left) - margin, wantT = Math.Min(en.Top, ec.Top) - margin;
      int wantR = Math.Max(en.Right, ec.Right) + margin, wantB = Math.Max(en.Bottom, ec.Bottom) + margin;
      bool ok = fr.Left == wantL && fr.Top == wantT && fr.Right == wantR && fr.Bottom == wantB;
      boxGeom = string.Format("frame {0},{1}-{2},{3} expected {4},{5}-{6},{7} -> {8}",
                              fr.Left, fr.Top, fr.Right, fr.Bottom,
                              wantL, wantT, wantR, wantB, ok ? "exact" : "MISMATCH");
    }
    sInt.Sort(); cInt.Sort(); bInt.Sort();
    double smed = sInt.Count > 0 ? sInt[sInt.Count / 2] : 0;
    double cmed = cInt.Count > 0 ? cInt[cInt.Count / 2] : 0;
    double bmed = bInt.Count > 0 ? bInt[bInt.Count / 2] : 0;
    double span = Math.Max(1, endT - 100);
    var sb = new StringBuilder();
    sb.AppendFormat("strip {0} {1},{2} {3}x{4} | companion {5} {6},{7} {8}x{9} visible={10}\n",
                    strip, s0.Left, s0.Top, s0.Right - s0.Left, s0.Bottom - s0.Top,
                    comp, ec.Left, ec.Top, ec.Right - ec.Left, ec.Bottom - ec.Top,
                    IsWindowVisible(comp));
    sb.AppendFormat("injected {0} steps over {1:F0} ms\n", steps, endT);
    sb.AppendFormat("strip:     {0} moves ({1:F1}/s) median {2:F1} ms max {3:F1} ms\n",
                    sCh, sCh * 1000.0 / span, smed, maxSGap);
    sb.AppendFormat("companion: {0} moves ({1:F1}/s) median {2:F1} ms max {3:F1} ms\n",
                    cCh, cCh * 1000.0 / span, cmed, maxCGap);
    if (box != IntPtr.Zero)
      sb.AppendFormat("frame:     {0} moves ({1:F1}/s) median {2:F1} ms max {3:F1} ms\n",
                      bCh, bCh * 1000.0 / span, bmed, maxBGap);
    sb.AppendFormat("ratio companion/strip: {0:F2}\n", sCh > 0 ? (double)cCh / sCh : 0);
    if (countStale)
      sb.AppendFormat("samples where the strip moved but the companion did not: {0}\n", staleFrames);
    sb.AppendFormat("separation from the rest offset: companion mean {0:F2} px max {1:F0} px | frame mean {2:F2} px max {3:F0} px\n",
                    sepN > 0 ? sepSum / sepN : 0, sepMax, sepN > 0 ? bsepSum / sepN : 0, bsepMax);
    sb.AppendFormat("offset at start {0},{1} -> at end {2},{3} (drift {4},{5})\n",
                    off0x, off0y, off1x, off1y, off1x - off0x, off1y - off0y);
    sb.AppendFormat("{0}\n", boxGeom);
    sb.AppendFormat("strip walked back to {0}\n", back);
    return sb.ToString();
  }
}
"@
[void][FollowFps]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [FollowFps]::Find('DockStripWindow')
$comp  = [FollowFps]::Find('DockTrayBarWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no strip'; exit 1 }
if ($comp -eq [IntPtr]::Zero) { Write-Output 'no companion'; exit 1 }
# grab the chevron: read it from the dock's own layout line (the formula is not trustworthy)
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
# Grab the Windows button (first slot), not the chevron: in the fully transparent profile the
# strip is hit-tested through its alpha, and the middle of the "^" glyph is a hole - a press
# there falls through to whatever is behind (measured: Chrome_RenderWidgetHostWidget).
# The Win button's four squares are opaque, and pressing it and dragging moves the strip the
# same way the chevron does.
Write-Output "grabbing the Windows button at client 46,46"
$box = [FollowFps]::Find('DockGroupBoxWindow')
Write-Output ([FollowFps]::Run($strip, $comp, $Dx, $Dy, $Ms, $StepsPerSec, 46, 46, $box, $Margin))

