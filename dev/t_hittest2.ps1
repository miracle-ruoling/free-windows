. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Z {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Info(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    var c = new StringBuilder(128); GetClassName(h, c, 128);
    var t = new StringBuilder(128); GetWindowText(h, t, 128);
    RC r; GetWindowRect(h, out r);
    uint pid; GetWindowThreadProcessId(h, out pid);
    int ex = GetWindowLong(h, -20);
    return string.Format("{0} pid={1} {2} '{3}' {4},{5} {6}x{7} vis={8} en={9} ex=0x{10:X8} through={11} topmost={12}",
      h, pid, c, t, r.L, r.T, r.R-r.L, r.B-r.T, IsWindowVisible(h), IsWindowEnabled(h), ex, (ex & 0x20) != 0, (ex & 0x8) != 0);
  }
  public static string At(int x, int y) {
    IntPtr h = WindowFromPoint(new POINT{X=x,Y=y});
    return Info(h);
  }
  public static string ZOrder() {
    var sb = new StringBuilder();
    int i = 0;
    for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero && i < 60; h = GetWindow(h, 2), i++) {
      var c = new StringBuilder(64); GetClassName(h, c, 64);
      if (!c.ToString().StartsWith("Dock")) continue;
      sb.AppendFormat("z#{0} {1}\n", i, Info(h));
    }
    return sb.ToString();
  }
}
"@
Write-Output '--- our windows in z-order (top first) ---'
Write-Output ([Z]::ZOrder())
$strip = [S]::ByClass('DockStripWindow')
$r = New-Object S+RECT; [void][S]::GetWindowRect($strip, [ref]$r)
Write-Output ("strip rect " + $r.Left + "," + $r.Top + "-" + $r.Right + "," + $r.Bottom)
for ($i = 0; $i -lt 8; $i++) {
  $x = 452 + 22 + $i * 78 + 36
  $y = $r.Top + 48
  if ($r.Top -lt 0) { $y = 28 + 48 }
  Write-Output ("  cell {0} at {1},{2} -> {3}" -f $i, $x, $y, [Z]::At($x, $y))
}
