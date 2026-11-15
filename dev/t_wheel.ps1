# Inject wheel notches at a screen point (used to test the tray bar's volume wheel and, as a
# control, the strip's paging). The wheel message goes to the window under the pointer, so a
# real injection is the only honest test - PostMessage would bypass the routing we care about.
#
#   .\t_wheel.ps1 -X 1384 -Y 176 -Notches 3      # +3 detents (volume up / scroll up)
#   .\t_wheel.ps1 -X 1200 -Y 200 -Notches -3     # -3 detents
param([Parameter(Mandatory = $true)] [int]$X, [Parameter(Mandatory = $true)] [int]$Y,
      [int]$Notches = 1, [int]$GapMs = 120, [int]$HoldMs = 400)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class WheelInj {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Go(int x, int y, int notches, int gapMs, int holdMs) {
    SetCursorPos(x, y);
    Thread.Sleep(holdMs);
    POINT p; p.X = x; p.Y = y;
    IntPtr under = WindowFromPoint(p);
    StringBuilder b = new StringBuilder(160);
    if (under != IntPtr.Zero) GetClassName(under, b, 160);
    for (int i = 0; i < Math.Abs(notches); i++) {
      int d = notches > 0 ? 120 : -120;
      mouse_event(0x0800, 0, 0, unchecked((uint)d), UIntPtr.Zero);
      Thread.Sleep(gapMs);
    }
    Thread.Sleep(holdMs);
    return x + "," + y + " (" + notches + " notches) over " +
           (under == IntPtr.Zero ? "(desktop)" : b.ToString());
  }
}
"@
[void][WheelInj]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([WheelInj]::Go($X, $Y, $Notches, $GapMs, $HoldMs))
