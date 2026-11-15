# Drag the tray bar with a real mouse (down inside a cell, move, release) and report.
param([int]$Dx = 80, [int]$Dy = 40)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class TD1 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
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
  public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
}
"@
[void][TD1]::SetProcessDpiAwarenessContext([IntPtr](-4))
$h = [TD1]::Find('DockTrayBarWindow')
if ($h -eq [IntPtr]::Zero) { Write-Output "no tray bar"; exit 1 }
$r = [TD1]::Rect($h)
Write-Output ("before: " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))

# grab the first cell (its centre is drawn, so the layered window takes the press)
$gx = $r.Left + 46
$gy = $r.Top + ($r.Bottom - $r.Top) / 2
[void][TD1]::SetCursorPos($gx, $gy)
Start-Sleep -Milliseconds 250
[TD1]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
for ($i = 1; $i -le 10; $i++) {
    [void][TD1]::SetCursorPos($gx + [int]($Dx * $i / 10), $gy + [int]($Dy * $i / 10))
    Start-Sleep -Milliseconds 45
}
Start-Sleep -Milliseconds 120
[TD1]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
$r2 = [TD1]::Rect($h)
Write-Output ("after:  " + $r2.Left + "," + $r2.Top + " " + ($r2.Right-$r2.Left) + "x" + ($r2.Bottom-$r2.Top))
Write-Output ("moved by " + ($r2.Left - $r.Left) + "," + ($r2.Top - $r.Top))
