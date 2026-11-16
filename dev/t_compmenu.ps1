# Open the tray bar's menu and pick one item by screen coordinates.
#
# Used to verify the menu commands actually run (the menu itself is a plain TrackPopupMenu, so
# the only thing worth testing is "does the command do what it says"). The group is warmed up
# first because the tray bar is only on screen while the pointer is on the strip.
#
#   .\t_menupick.ps1 -X 1384 -Y 176 -PickX 1450 -PickY 239
param([Parameter(Mandatory = $true)] [int]$X, [Parameter(Mandatory = $true)] [int]$Y,
      [Parameter(Mandatory = $true)] [int]$PickX, [Parameter(Mandatory = $true)] [int]$PickY)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class MP {
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
    // Several DockGroupBoxWindow exist since G2 (one per group, created up front and hidden):
    // always prefer the visible one.
    IntPtr first = IntPtr.Zero, visible = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() != cls) return true;
      if (first == IntPtr.Zero) first = h;
      if (Show(h)) { visible = h; return false; }
      return true; }, IntPtr.Zero);
    return visible != IntPtr.Zero ? visible : first;
  }
  static bool Show(IntPtr h) { return IsWindowVisibleNative(h); }
  [DllImport("user32.dll", EntryPoint = "IsWindowVisible")] static extern bool IsWindowVisibleNative(IntPtr h);
  public static string Go(int x, int y, int px, int py) {
    IntPtr strip = Find("DockStripWindow");
    RECT s; GetWindowRect(strip, out s);
    SetCursorPos((s.Left + s.Right) / 2, (s.Top + s.Bottom) / 2);
    Thread.Sleep(600);
    IntPtr box = Find("DockGroupBoxWindow");
    string before = box == IntPtr.Zero ? "no frame window" : ("frame visible=" + IsWindowVisible(box));
    SetCursorPos(x, y);
    Thread.Sleep(350);
    mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(70);
    mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(450);
    SetCursorPos(px, py);
    Thread.Sleep(200);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(70);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(600);
    box = Find("DockGroupBoxWindow");
    string after = box == IntPtr.Zero ? "no frame window" : ("frame visible=" + IsWindowVisible(box));
    return "right-click " + x + "," + y + " then pick " + px + "," + py + "\n  before: " + before +
           "\n  after:  " + after;
  }
}
"@
[void][MP]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([MP]::Go($X, $Y, $PickX, $PickY))
