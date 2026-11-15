# Open the quick settings panel (Win+A) and identify the window that draws it.
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QS {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Info(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    uint pid; GetWindowThreadProcessId(h, out pid);
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    StringBuilder t = new StringBuilder(128); GetWindowText(h, t, 128);
    RECT r; GetWindowRect(h, out r);
    return string.Format("h={0} pid={1} cls={2} txt='{3}' rect={4},{5} {6}x{7}", h.ToInt64(), pid, b, t, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top);
  }
  public static string At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    return Info(GetAncestor(WindowFromPoint(p), 2));
  }
  public static void OpenWinA() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(70);
    keybd_event(0x41, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x41, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(70);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
  public static string Fg() { return Info(GetForegroundWindow()); }
}
"@
[void][QS]::SetProcessDpiAwarenessContext([IntPtr](-4))
[QS]::Esc(); Start-Sleep -Milliseconds 600
[QS]::OpenWinA()
Start-Sleep -Milliseconds 1300
Write-Output ("foreground: " + [QS]::Fg())
foreach ($pt in @(@(1700, 400), @(1700, 600), @(1700, 800), @(1800, 950))) {
    Write-Output ("$($pt[0]),$($pt[1]) -> " + [QS]::At($pt[0], $pt[1]))
}
[QS]::Esc()
Start-Sleep -Milliseconds 400
Write-Output "closed"
