# Right-click at a screen point after warming the group up (the tray bar only exists on screen
# while the pointer is on the strip, so a cold right click would land on whatever is behind it).
# The menu is left open on purpose - capture it from another process, then close it with
# t_sendkey.ps1 -Key 27.
#
#   .\t_rclick.ps1 -X 1384 -Y 176
param([Parameter(Mandatory = $true)] [int]$X, [Parameter(Mandatory = $true)] [int]$Y)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class RC {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
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
  public static string Go(int x, int y) {
    IntPtr strip = Find("DockStripWindow");
    if (strip != IntPtr.Zero) {
      RECT s; GetWindowRect(strip, out s);
      SetCursorPos((s.Left + s.Right) / 2, (s.Top + s.Bottom) / 2);
      Thread.Sleep(600);                       // let the group fade in
    }
    SetCursorPos(x, y);
    Thread.Sleep(350);
    POINT p; p.X = x; p.Y = y;
    IntPtr under = WindowFromPoint(p);
    StringBuilder b2 = new StringBuilder(160);
    if (under != IntPtr.Zero) GetClassName(under, b2, 160);
    mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero);   // right down
    Thread.Sleep(70);
    mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);   // right up
    Thread.Sleep(500);
    return "right-clicked " + x + "," + y + " over " + (under == IntPtr.Zero ? "(desktop)" : b2.ToString());
  }
}
"@
[void][RC]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([RC]::Go($X, $Y))
