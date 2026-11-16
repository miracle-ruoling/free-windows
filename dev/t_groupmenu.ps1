# G1 probe: pick an item from the GROUP menu (right-click on the board or on the frame line).
#
# The group menu is a plain TrackPopupMenu, so what needs testing is that the command runs.
# Items: 1 显示边框线 / 2 屏蔽缩放 / 3 屏蔽位移 / 4 Dock 设置…
# (menu item offsets below were measured on this machine's theme: +9 / +36 / +63 / +104 with a
#  separator before the last one.)
#
#   .\t_groupmenu.ps1 -Item 2            # toggle 屏蔽缩放, on the frame's left edge
#   .\t_groupmenu.ps1 -Item 3 -X 900 -Y 200   # choose the point yourself (e.g. the board)
param([int]$Item = 1, [int]$X = 0, [int]$Y = 0)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class GM {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
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
  public static string Name(IntPtr h) {
    if (h == IntPtr.Zero) return "(desktop)";
    StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
    return b.ToString();
  }
  public static string Go(int item, int x, int y) {
    IntPtr strip = Find("DockStripWindow"), box = Find("DockGroupBoxWindow");
    RECT s; GetWindowRect(strip, out s);
    SetCursorPos((s.Left + s.Right) / 2, (s.Top + s.Bottom) / 2);
    Thread.Sleep(600);
    if (x == 0 && y == 0) {
      RECT b; GetWindowRect(box, out b);
      x = b.Left + 4;                      // on the frame line / grab ring
      y = (b.Top + b.Bottom) / 2;
    }
    SetCursorPos(x, y);
    Thread.Sleep(350);
    POINT p; p.X = x; p.Y = y;
    string under = Name(WindowFromPoint(p));
    mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(70);
    mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(500);
    int off = 9;
    if (item == 2) off = 36;
    else if (item == 3) off = 63;
    else if (item == 4) off = 104;
    SetCursorPos(x + 60, y + off);
    Thread.Sleep(200);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(70);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(500);
    RECT b2; GetWindowRect(box, out b2);
    return "right-clicked " + x + "," + y + " over " + under + " -> picked item " + item +
           " at +" + off + "\n  frame now " + b2.Left + "," + b2.Top + "-" + b2.Right + "," +
           b2.Bottom + " visible=" + IsWindowVisible(box);
  }
}
"@
[void][GM]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([GM]::Go($Item, $X, $Y))
Start-Sleep -Milliseconds 300
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
(Get-Content $log | Where-Object { $_.Trim() -ne '' } |
    Select-String -Pattern 'group: menu ->' | Select-Object -Last 2) | ForEach-Object { "  log: " + $_.Line }
