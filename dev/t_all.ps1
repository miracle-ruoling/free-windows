. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class EN {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static string Dump() {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      var c = new StringBuilder(128); GetClassName(h, c, 128);
      var cls = c.ToString();
      if (!cls.StartsWith("Dock")) return true;
      var t = new StringBuilder(128); GetWindowText(h, t, 128);
      RC r; GetWindowRect(h, out r);
      uint pid; GetWindowThreadProcessId(h, out pid);
      sb.AppendFormat("{0} pid={1} {2} '{3}' {4},{5} {6}x{7} vis={8}\n", h, pid, cls, t, r.L, r.T, r.R-r.L, r.B-r.T, IsWindowVisible(h));
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
"@
Write-Output ([EN]::Dump())
