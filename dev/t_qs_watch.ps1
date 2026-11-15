# Click the tray bar and watch the foreground window class for 2 s.
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QW {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
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
  public static string FgClass() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    RECT r; GetWindowRect(h, out r);
    return b + " rect=" + r.Left + "," + r.Top + " " + (r.Right-r.Left) + "x" + (r.Bottom-r.Top);
  }
  public static string At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    IntPtr h = GetAncestor(WindowFromPoint(p), 2);
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    RECT r; GetWindowRect(h, out r);
    return b + " rect=" + r.Left + "," + r.Top + " " + (r.Right-r.Left) + "x" + (r.Bottom-r.Top);
  }
}
"@
[void][QW]::SetProcessDpiAwarenessContext([IntPtr](-4))
$bar = [QW]::Find('DockTrayBarWindow')
$br = New-Object QW+RECT
[void][QW]::GetWindowRect($bar, [ref]$br)
Write-Output ("tray bar at " + $br.Left + "," + $br.Top + " " + ($br.Right-$br.Left) + "x" + ($br.Bottom-$br.Top))
$strip = [QW]::Find('DockStripWindow')
$sr = New-Object QW+RECT
[void][QW]::GetWindowRect($strip, [ref]$sr)
[void][QW]::SetCursorPos($sr.Left + 30, ($sr.Top + $sr.Bottom) / 2)
Start-Sleep -Milliseconds 500
[void][QW]::SetCursorPos($br.Left + 30, ($br.Top + $br.Bottom) / 2)
Start-Sleep -Milliseconds 250
[QW]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[QW]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "clicked; polling foreground:"
for ($i = 0; $i -lt 16; $i++) {
    Start-Sleep -Milliseconds 120
    Write-Output ("  +" + (($i + 1) * 120) + "ms  fg=" + [QW]::FgClass())
}
