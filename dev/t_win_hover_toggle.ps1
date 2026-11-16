# Exercise the taskbar mod's decision points without the dock's own chords:
#   hover the bottom edge, then tap Win twice. Reports the bar before/after each step.
param([int]$HoverMs = 5000)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class WP {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static int ScreenH() { return GetSystemMetrics(1); }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? "  HIDDEN" : "  ON SCREEN"); }
  public static void Move(int x, int y) { SetCursorPos(x, y); }
  public static void Tap(byte vk) { keybd_event(vk,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk,0,2,UIntPtr.Zero); }
}
"@
[void][WP]::SetProcessDpiAwarenessContext([IntPtr](-4))
$h = [WP]::ScreenH()
$save = New-Object WP+POINT
"start:              " + [WP]::Bar()
"--- hover the bottom edge for $HoverMs ms ---"
[WP]::Move(900, $h - 1)
Start-Sleep -Milliseconds $HoverMs
"after hover:        " + [WP]::Bar()
[WP]::Move(900, $h - 400)
Start-Sleep -Milliseconds 400
"--- Win tap 1 ---"
[WP]::Tap(0x5B)
Start-Sleep -Milliseconds 2000
"after win1:         " + [WP]::Bar()
"--- Win tap 2 ---"
[WP]::Tap(0x5B)
Start-Sleep -Milliseconds 1500
"after win2:         " + [WP]::Bar()
[WP]::Tap(0x1B)
Start-Sleep -Milliseconds 500
"after esc:          " + [WP]::Bar()
