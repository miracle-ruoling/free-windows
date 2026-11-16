# Where do two windows sit in the z-order, relative to each other? (G1: the group board must end
# up *below* shell flyouts, otherwise it eats their clicks.)
#
#   .\t_zorder.ps1
param([string[]]$Classes = @('DockGroupBoxWindow', 'DockStripWindow', 'DockTrayBarWindow', 'ControlCenterWindow'))
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class ZO {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Run(string[] want) {
    var seen = new Dictionary<string, string>();
    int idx = 0;
    for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero; h = GetWindow(h, 2 /*GW_HWNDNEXT*/)) {
      idx++;
      var b = new StringBuilder(160);
      GetClassName(h, b, 160);
      string cls = b.ToString();
      foreach (string w in want) {
        if (cls == w && !seen.ContainsKey(w)) {
          RECT r; GetWindowRect(h, out r);
          bool topmost = (GetWindowLong(h, -20 /*GWL_EXSTYLE*/) & 0x8) != 0;
          seen[w] = "z#" + idx + " (topmost=" + topmost + ") " + r.Left + "," + r.Top + "-" +
                    r.Right + "," + r.Bottom + " visible=" + IsWindowVisible(h);
        }
      }
      if (idx > 4000) break;
    }
    var sb = new StringBuilder();
    sb.AppendLine("z-order index: smaller = higher on screen");
    foreach (string w in want)
      sb.AppendLine("  " + w.PadRight(22) + (seen.ContainsKey(w) ? seen[w] : "(not found)"));
    return sb.ToString();
  }
}
"@
[void][ZO]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([ZO]::Run($Classes))
