# What is actually at these screen points? (WindowFromPoint is the only reliable answer for
# layered windows hit-tested through their alpha - EnumWindows does not even list some shells.)
#
#   .\t_hit_at.ps1 1518 236 1500 240
param([Parameter(ValueFromRemainingArguments = $true)] [int[]]$Points)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Hit {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    IntPtr h = WindowFromPoint(p);
    if (h == IntPtr.Zero) return x + "," + y + " -> nothing (desktop)";
    StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
    return x + "," + y + " -> " + h + " " + b.ToString();
  }
}
"@
[void][Hit]::SetProcessDpiAwarenessContext([IntPtr](-4))
if ($Points.Count -lt 2) { Write-Output "usage: t_hit_at.ps1 x1 y1 [x2 y2 ...]"; exit 1 }
for ($i = 0; $i + 1 -lt $Points.Count; $i += 2) {
    Write-Output ([Hit]::At($Points[$i], $Points[$i + 1]))
}
