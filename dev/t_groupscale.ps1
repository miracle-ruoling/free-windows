# R3 probe: drag the frame's right edge and check that the whole group scales by the same ratio.
#
# The frame IS the handle (user, 2026-11-16: "把组在长、宽上的变化比例也应用给条的外框"). Expected:
#   * the frame follows the pointer (+Dx), the left edge stays put;
#   * the strip's and the companion's rectangles scale by the same factor about that edge;
#   * a click inside the frame still falls through, the grab ring does not;
#   * the frame is re-derived from the members afterwards.
#
#   .\t_groupscale.ps1 [-Dx 200] [-Dy 0]
param([int]$Dx = 200, [int]$Dy = 0, [ValidateSet("right","bottom","corner","left","top")] [string]$Edge = "right")
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class GS {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
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
  public static string Name(IntPtr h) {
    if (h == IntPtr.Zero) return "(desktop)";
    StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
    return b.ToString();
  }
  static string R(RECT r) { return r.Left + "," + r.Top + "-" + r.Right + "," + r.Bottom +
                                   " (" + (r.Right - r.Left) + "x" + (r.Bottom - r.Top) + ")"; }
  public static string Run(IntPtr strip, IntPtr comp, IntPtr box, int dx, int dy, string edge) {
    RECT s0; GetWindowRect(strip, out s0);
    SetCursorPos((s0.Left + s0.Right) / 2, (s0.Top + s0.Bottom) / 2);
    Thread.Sleep(500);                                   // frame fades in, pointer on the strip
    RECT b0; GetWindowRect(box, out b0);
    if (!IsWindowVisible(box)) return "frame not visible - is the pointer on the strip?";
    RECT c0; GetWindowRect(comp, out c0);

    // grab the ring: it is min(margin,10)+lineWidth px wide, just inside the frame line
    int gx, gy;
    switch (edge) {
      case "bottom": gx = (b0.Left + b0.Right) / 2; gy = b0.Bottom - 4; break;
      case "corner": gx = b0.Right - 4; gy = b0.Bottom - 4; break;
      case "left":   gx = b0.Left + 4;  gy = (b0.Top + b0.Bottom) / 2; break;
      case "top":    gx = (b0.Left + b0.Right) / 2; gy = b0.Top + 4; break;
      default:       gx = b0.Right - 4; gy = (b0.Top + b0.Bottom) / 2; break;
    }
    var sb = new StringBuilder();
    sb.AppendFormat("before: frame {0} | strip {1} | companion {2}\n", R(b0), R(s0), R(c0));
    POINT probe; probe.X = b0.Right - 4; probe.Y = (b0.Top + b0.Bottom) / 2;
    sb.AppendFormat("hit on the ring: {0} | hit in the middle: {1}\n",
                    Name(WindowFromPoint(probe)),
                    Name(WindowFromPoint(new POINT { X = (b0.Left + b0.Right) / 2,
                                                    Y = (b0.Top + b0.Bottom) / 2 })));
    SetCursorPos(gx, gy);
    Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(80);
    if (ThreadCapture(box) != box) {
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      return sb.ToString() + "press did not land on the frame (capture " + ThreadCapture(box) + ")\n";
    }
    for (int i = 1; i <= 15; i++) {
      SetCursorPos(gx + (int)((long)dx * i / 15), gy + (int)((long)dy * i / 15));
      Thread.Sleep(20);
    }
    Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(300);

    RECT s1, c1, b1;
    GetWindowRect(strip, out s1); GetWindowRect(comp, out c1); GetWindowRect(box, out b1);
    sb.AppendFormat("after:  frame {0} | strip {1} | companion {2}\n", R(b1), R(s1), R(c1));
    double want = (b0.Right - b0.Left - 2 * 8) + dx;      // members' bbox + dx
    double sxStrip = (double)(s1.Right - s1.Left) / (s0.Right - s0.Left);
    double sxComp = (double)(c1.Right - c1.Left) / (c0.Right - c0.Left);
    sb.AppendFormat("frame width {0} -> {1} (wanted about {2:F0})\n",
                    b0.Right - b0.Left, b1.Right - b1.Left, want + 2 * 8);
    sb.AppendFormat("strip width x{0:F3}, companion width x{1:F3} (should match)\n", sxStrip, sxComp);
    sb.AppendFormat("left edges: strip {0}->{1}, companion {2}->{3} (right-edge drag: should not move)\n",
                    s0.Left, s1.Left, c0.Left, c1.Left);
    sb.AppendFormat("frame == members + margin: {0}\n",
                    (b1.Left == Math.Min(s1.Left, c1.Left) - 8 && b1.Top == Math.Min(s1.Top, c1.Top) - 8 &&
                     b1.Right == Math.Max(s1.Right, c1.Right) + 8 && b1.Bottom == Math.Max(s1.Bottom, c1.Bottom) + 8));
    return sb.ToString();
  }
}
"@
[void][GS]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [GS]::Find('DockStripWindow'); $comp = [GS]::Find('DockTrayBarWindow'); $box = [GS]::Find('DockGroupBoxWindow')
if ($strip -eq [IntPtr]::Zero -or $comp -eq [IntPtr]::Zero -or $box -eq [IntPtr]::Zero) {
    Write-Output 'missing window'; exit 1
}
Write-Output ([GS]::Run($strip, $comp, $box, $Dx, $Dy, $Edge))

