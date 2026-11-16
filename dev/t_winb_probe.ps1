# Send Win+B (the chord the dock uses to focus the notification area) and watch the bar.
param([int]$Delay = 0)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class WB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? "  HIDDEN" : "  ON SCREEN"); }
  public static string Fg() {
    IntPtr h = GetForegroundWindow();
    var sb = new System.Text.StringBuilder(200); GetClassName(h, sb, 200);
    return "fg='" + sb + "'"; }
  public static string Watch(int ms) {
    int minY = 99999, maxY = -99999; var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) {
      IntPtr h = FindWindow("Shell_TrayWnd", null);
      if (h != IntPtr.Zero) { RECT r; if (GetWindowRect(h, out r)) { if (r.Top < minY) minY = r.Top; if (r.Top > maxY) maxY = r.Top; } }
      System.Threading.Thread.Sleep(8); }
    return "minY=" + minY + " maxY=" + maxY; }
  public static void WinB() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
}
"@
[void][WB]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ("start: " + [WB]::Bar())
if ($Delay -gt 0) { Start-Sleep -Milliseconds $Delay }
[WB]::WinB()
Write-Output ("watch: " + [WB]::Watch(1500))
Write-Output ("after: " + [WB]::Bar() + "   " + [WB]::Fg())
keybd_event(0,0,0,[UIntPtr]::Zero) | Out-Null
