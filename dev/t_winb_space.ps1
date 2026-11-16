# Does Space open the shell's overflow flyout after Win+B even when the taskbar never
# expands? (The dock currently requires the bar rect to rise before pressing Space.)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class BS {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found; }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? " HIDDEN" : " ON SCREEN"); }
  public static string Fly() {
    IntPtr f = Find("TopLevelWindowForOverflowXamlIsland");
    if (f == IntPtr.Zero) return "flyout: none";
    RECT r; GetWindowRect(f, out r);
    return "flyout: " + f.ToString("X") + " vis=" + IsWindowVisible(f) + " rect=" + r.Left + "," + r.Top + " " + (r.Right-r.Left) + "x" + (r.Bottom-r.Top); }
  public static void WinB() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
  public static void Space() { keybd_event(0x20,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(50); keybd_event(0x20,0,2,UIntPtr.Zero); }
  public static bool FgIsTray() { IntPtr h = FindWindow("Shell_TrayWnd", null); return GetForegroundWindow() == h; }
}
"@
[void][BS]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ("start:  " + [BS]::Bar() + "   " + [BS]::Fly())
[BS]::WinB()
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 10; if ([BS]::FgIsTray()) { break } }
Write-Output ("after Win+B: " + [BS]::Bar() + "   fgIsTray=" + [BS]::FgIsTray())
[BS]::Space()
Start-Sleep -Milliseconds 700
Write-Output ("after Space: " + [BS]::Bar() + "   " + [BS]::Fly())
Start-Sleep -Milliseconds 800
Write-Output ("+0.8 s:      " + [BS]::Bar() + "   " + [BS]::Fly())
