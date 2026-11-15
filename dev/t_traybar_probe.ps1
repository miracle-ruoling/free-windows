# Is the tray bar window alive, where, and visible?
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class TW1 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Dump() {
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      string c = b.ToString();
      if (c != "DockTrayBarWindow") return true;
      RECT r; GetWindowRect(h, out r);
      uint pid; GetWindowThreadProcessId(h, out pid);
      Console.WriteLine(string.Format("traybar h={0} pid={1} vis={2} rect={3},{4} {5}x{6} ex=0x{7:X8}",
        h.ToInt64(), pid, IsWindowVisible(h), r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, GetWindowLong(h, -20)));
      return true; }, IntPtr.Zero);
  }
}
"@
[void][TW1]::SetProcessDpiAwarenessContext([IntPtr](-4))
[TW1]::Dump()
