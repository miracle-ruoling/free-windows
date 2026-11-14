Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class W {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static List<string> List() {
    List<string> l = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
      if (t.Length == 0) return true;
      StringBuilder c = new StringBuilder(120); GetClassName(h, c, 120);
      uint pid; GetWindowThreadProcessId(h, out pid);
      RECT r; GetWindowRect(h, out r);
      if (r.Right - r.Left < 40) return true;
      l.Add(string.Format("{0,8} pid={1,-6} {2,5}x{3,-4} at {4},{5}  {6} | {7}", h, pid, r.Right-r.Left, r.Bottom-r.Top, r.Left, r.Top, c.ToString(), t.ToString()));
      return true;
    }, IntPtr.Zero);
    return l;
  }
}
"@
[W]::List() | ForEach-Object { Write-Output $_ }
