# Why did the injected click miss the strip? Report the window under a point and the
# strip's metrics around it.
param([int]$X = -1, [int]$Y = -1)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WD3 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static string Info(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    uint pid; GetWindowThreadProcessId(h, out pid);
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    StringBuilder t = new StringBuilder(128); GetWindowText(h, t, 128);
    RECT r; GetWindowRect(h, out r);
    return string.Format("h={0} pid={1} cls={2} txt='{3}' rect={4},{5} {6}x{7} ex=0x{8:X8}",
      h.ToInt64(), pid, b, t, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, GetWindowLong(h, -20));
  }
}
"@
[void][WD3]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [WD3]::Find('DockStripWindow')
Write-Output ("strip: " + [WD3]::Info($strip))
$r = New-Object WD3+RECT
[void][WD3]::GetWindowRect($strip, [ref]$r)
if ($X -lt 0) { $X = [int](($r.Left + $r.Right) / 2); $Y = [int](($r.Top + $r.Bottom) / 2) }
$ok = [WD3]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 200
$p = New-Object WD3+POINT
[void][WD3]::GetCursorPos([ref]$p)
Write-Output ("SetCursorPos(" + $X + "," + $Y + ")=" + $ok + " -> cursor now " + $p.X + "," + $p.Y)
$hit = [WD3]::WindowFromPoint($p)
Write-Output ("window under the cursor: " + [WD3]::Info($hit))
Write-Output ("its root: " + [WD3]::Info([WD3]::GetAncestor($hit, 2)))
