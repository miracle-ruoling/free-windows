# Is the tray bar actually visible and on top at a point inside it?
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QX {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
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
  public static string At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    IntPtr h = GetAncestor(WindowFromPoint(p), 2);
    uint pid; GetWindowThreadProcessId(h, out pid);
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    return "h=" + h.ToInt64() + " pid=" + pid + " cls=" + b;
  }
}
"@
[void][QX]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [QX]::Find('DockStripWindow')
$bar = [QX]::Find('DockTrayBarWindow')
$sr = New-Object QX+RECT; [void][QX]::GetWindowRect($strip, [ref]$sr)
$br = New-Object QX+RECT; [void][QX]::GetWindowRect($bar, [ref]$br)
Write-Output ("strip " + $sr.Left + "," + $sr.Top + " " + ($sr.Right-$sr.Left) + "x" + ($sr.Bottom-$sr.Top))
Write-Output ("bar   " + $br.Left + "," + $br.Top + " " + ($br.Right-$br.Left) + "x" + ($br.Bottom-$br.Top) + " visible=" + [QX]::IsWindowVisible($bar))
[void][QX]::SetCursorPos($sr.Left + 40, [int](($sr.Top + $sr.Bottom) / 2))
Start-Sleep -Milliseconds 600
Write-Output ("after hovering the strip: bar visible=" + [QX]::IsWindowVisible($bar))
Write-Output ("  hit at bar centre -> " + [QX]::At([int](($br.Left + $br.Right) / 2), [int](($br.Top + $br.Bottom) / 2)))
[void][QX]::SetCursorPos([int](($br.Left + $br.Right) / 2), [int](($br.Top + $br.Bottom) / 2))
Start-Sleep -Milliseconds 400
Write-Output ("after moving onto the bar: visible=" + [QX]::IsWindowVisible($bar))
Write-Output ("  hit at bar centre -> " + [QX]::At([int](($br.Left + $br.Right) / 2), [int](($br.Top + $br.Bottom) / 2)))
