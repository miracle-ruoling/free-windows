# G1 probe: drag the group by grabbing the board (the empty space inside the frame).
#
# The board only exists where no member sits; in a tightly packed group that is just the margin
# ring, which the resize handle already owns - so this probe wants a roomy `[group] margin`
# (e.g. 40) to have somewhere to grab. What it verifies:
#   * a press on the board is received at all (alpha 1 is enough to be hit-tested);
#   * the WHOLE group moves by the same delta (strip + companion + frame);
#   * the frame stays exactly members + margin afterwards;
#   * the ini gets the new positions (so a restart keeps them).
#
#   .\t_groupdrag.ps1 [-Dx 200] [-Dy 120] [-Inset 20]
param([int]$Dx = 200, [int]$Dy = 120, [int]$Inset = 20, [int]$Margin = 40, [int]$Steps = 20, [int]$StepMs = 16)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class GD {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
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
  public static string Run(IntPtr strip, IntPtr comp, IntPtr box, int dx, int dy, int inset,
                           int margin, int steps, int stepMs) {
    RECT s0; GetWindowRect(strip, out s0);
    SetCursorPos((s0.Left + s0.Right) / 2, (s0.Top + s0.Bottom) / 2);
    Thread.Sleep(600);
    RECT b0, c0; GetWindowRect(box, out b0); GetWindowRect(comp, out c0);
    if (!IsVisible(box)) return "frame not visible - pointer not on the strip?";
    if (b0.Right - b0.Left < 2 * margin + 20)
      return "frame too small for this test: " + R(b0) + " - set [group] margin=" + margin +
             " and restart";

    // grab point: `inset` px inside the left edge, half height -> outside the ring (<=10 px)
    // and outside every member (the margin band is empty by construction)
    int gx = b0.Left + inset, gy = (b0.Top + b0.Bottom) / 2;
    POINT probe; probe.X = gx; probe.Y = gy;
    var sb = new StringBuilder();
    sb.AppendFormat("before: frame {0} | strip {1} | companion {2}\n", R(b0), R(s0), R(c0));
    sb.AppendFormat("grab {0},{1} -> under the pointer: {2}\n", gx, gy, Name(WindowFromPoint(probe)));
    SetCursorPos(gx, gy);
    Thread.Sleep(200);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(80);
    if (ThreadCapture(box) != box) {
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      sb.AppendFormat("press did not land on the frame (capture {0}) - board not hit-testable\n",
                      ThreadCapture(box));
      return sb.ToString();
    }
    for (int i = 1; i <= steps; i++) {
      SetCursorPos(gx + (int)((long)dx * i / steps), gy + (int)((long)dy * i / steps));
      Thread.Sleep(stepMs);
    }
    Thread.Sleep(150);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(350);

    RECT s1, c1, b1;
    GetWindowRect(strip, out s1); GetWindowRect(comp, out c1); GetWindowRect(box, out b1);
    sb.AppendFormat("after:  frame {0} | strip {1} | companion {2}\n", R(b1), R(s1), R(c1));
    sb.AppendFormat("strip moved by {0},{1} (wanted about {2},{3})\n",
                    s1.Left - s0.Left, s1.Top - s0.Top, dx, dy);
    sb.AppendFormat("companion moved by {0},{1} (should match the strip)\n",
                    c1.Left - c0.Left, c1.Top - c0.Top);
    sb.AppendFormat("frame moved by {0},{1}; size {2}x{3} -> {4}x{5}\n",
                    b1.Left - b0.Left, b1.Top - b0.Top,
                    b0.Right - b0.Left, b0.Bottom - b0.Top,
                    b1.Right - b1.Left, b1.Bottom - b1.Top);
    sb.AppendFormat("frame == members + {0}: {1}\n", margin,
                    (b1.Left == Math.Min(s1.Left, c1.Left) - margin &&
                     b1.Top == Math.Min(s1.Top, c1.Top) - margin &&
                     b1.Right == Math.Max(s1.Right, c1.Right) + margin &&
                     b1.Bottom == Math.Max(s1.Bottom, c1.Bottom) + margin));
    return sb.ToString();
  }
  static bool IsVisible(IntPtr h) { return IsWindowVisibleNative(h); }
  [DllImport("user32.dll", EntryPoint = "IsWindowVisible")] static extern bool IsWindowVisibleNative(IntPtr h);
}
"@
[void][GD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [GD]::Find('DockStripWindow'); $comp = [GD]::Find('DockTrayBarWindow'); $box = [GD]::Find('DockGroupBoxWindow')
if ($strip -eq [IntPtr]::Zero -or $comp -eq [IntPtr]::Zero -or $box -eq [IntPtr]::Zero) {
    Write-Output 'missing window'; exit 1
}
Write-Output ([GD]::Run($strip, $comp, $box, $Dx, $Dy, $Inset, $Margin, $Steps, $StepMs))
