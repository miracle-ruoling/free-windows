# Does the dock own a visible tooltip window right now?
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class T3 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Dump(uint want) {
    int n = 0;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != want) return true;
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() != "tooltips_class32") return true;
      RECT r; GetWindowRect(h, out r);
      n++;
      Console.WriteLine(string.Format("tooltip h={0} vis={1} rect={2},{3} {4}x{5}", h.ToInt64(), IsWindowVisible(h), r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top));
      return true; }, IntPtr.Zero);
    if (n == 0) Console.WriteLine("no tooltip window for this pid");
  }
}
"@
$pid_ = (Get-Process dock).Id
Write-Output ("dock pid=" + $pid_)
[T3]::Dump([uint32]$pid_)
