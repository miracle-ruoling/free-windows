# Does Win+A open the quick settings panel right now? Report state step by step.
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QQ5 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
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
  public static IntPtr At(int x, int y) { POINT p; p.X = x; p.Y = y; return GetAncestor(WindowFromPoint(p), 2); }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static void WinA() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x41, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x41, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void WinTap() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(70);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
}
"@
[void][QQ5]::SetProcessDpiAwarenessContext([IntPtr](-4))
function State([string]$tag) {
    $bar = [QQ5]::Find('Shell_TrayWnd')
    $br = New-Object QQ5+RECT
    [void][QQ5]::GetWindowRect($bar, [ref]$br)
    $fg = [QQ5]::GetForegroundWindow()
    Write-Output ("[$tag] taskbar y=" + $br.Top + "  fg=" + [QQ5]::Info($fg))
    Write-Output ("      hit 1700,700 -> " + [QQ5]::Info([QQ5]::At(1700, 700)))
}
[QQ5]::Esc(); Start-Sleep -Milliseconds 700
State "closed"
[QQ5]::WinTap(); Start-Sleep -Milliseconds 900
State "after win tap (taskbar should toggle)"
[QQ5]::WinTap(); Start-Sleep -Milliseconds 900
State "after second win tap"
[QQ5]::WinA(); Start-Sleep -Milliseconds 1400
State "after win+a"
[QQ5]::Esc(); Start-Sleep -Milliseconds 500
State "after esc"
