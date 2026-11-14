Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class E {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Info { public IntPtr H; public string Cls; public string Txt; public uint Pid; public bool Vis; public RECT R; }
  public static List<Info> All() {
    List<Info> l = new List<Info>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      Info i = new Info(); i.H = h;
      StringBuilder b = new StringBuilder(256); GetClassName(h, b, 256); i.Cls = b.ToString();
      StringBuilder t = new StringBuilder(256); GetWindowText(h, t, 256); i.Txt = t.ToString();
      uint p; GetWindowThreadProcessId(h, out p); i.Pid = p;
      i.Vis = IsWindowVisible(h);
      RECT r; GetWindowRect(h, out r); i.R = r;
      l.Add(i);
      return true;
    }, IntPtr.Zero);
    return l;
  }
}
"@
$all = [E]::All()
Write-Output ("windows=" + $all.Count)
$all | Where-Object { $_.Cls -match 'Dock' } | ForEach-Object {
  Write-Output ("DOCK {0} cls={1} title='{2}' pid={3} vis={4} rect={5},{6}-{7},{8}" -f $_.H,$_.Cls,$_.Txt,$_.Pid,$_.Vis,$_.R.Left,$_.R.Top,$_.R.Right,$_.R.Bottom)
}
Write-Output ("distinct pids=" + (($all | ForEach-Object { $_.Pid } | Sort-Object -Unique).Count))
