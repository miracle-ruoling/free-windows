param([int]$Pid2 = 33920)
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class P {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static List<string> List(uint want) {
    List<string> l = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != want) return true;
      RECT r; GetWindowRect(h, out r);
      StringBuilder c = new StringBuilder(120); GetClassName(h, c, 120);
      StringBuilder t = new StringBuilder(120); GetWindowText(h, t, 120);
      IntPtr owner = GetWindow(h, 4);   // GW_OWNER
      l.Add(string.Format("{0} vis={1} sty=0x{2:X8} ex=0x{3:X8} {4},{5} {6}x{7} owner={8} cls={9} '{10}'",
        h, IsWindowVisible(h), GetWindowLong(h,-16), GetWindowLong(h,-20),
        r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, owner, c.ToString(), t.ToString()));
      return true;
    }, IntPtr.Zero);
    return l;
  }
}
"@
[P]::List([uint32]$Pid2) | ForEach-Object { Write-Output $_ }
