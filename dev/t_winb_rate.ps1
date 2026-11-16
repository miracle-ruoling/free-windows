# How often does Win+B actually hand the keyboard focus to the taskbar?
param([int]$Rounds = 6)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class RR {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static string Cls(IntPtr h) { var b = new StringBuilder(200); GetClassName(h, b, 200); return b.ToString(); }
  public static bool Tray() { return GetForegroundWindow() == FindWindow("Shell_TrayWnd", null); }
  public static string Fg() { return Cls(GetForegroundWindow()); }
  public static int BarTop() { RECT r; GetWindowRect(FindWindow("Shell_TrayWnd", null), out r); return r.Top; }
  public static void WinB(byte bvk) {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(bvk,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(bvk,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
  public static int WaitTray(int ms) {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) { if (Tray()) return (int)sw.ElapsedMilliseconds; System.Threading.Thread.Sleep(10); }
    return -1; }
}
"@
[void][RR]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ok = 0
for ($i = 1; $i -le $Rounds; $i++) {
    [RR]::WinB(0x42)
    $ms = [RR]::WaitTray(600)
    $top = [RR]::BarTop()
    if ($ms -ge 0) { $ok++ } 
    Write-Output ("round {0}: focus=tray after {1} ms, barTop={2}, fg='{3}'" -f $i, $ms, $top, [RR]::Fg())
    Start-Sleep -Milliseconds 900
    # give the focus back so the next round starts clean
    Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class E1 { [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e); }
"@
    [E1]::keybd_event(0x1B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [E1]::keybd_event(0x1B,0,2,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
Write-Output ("focus arrived in $ok / $Rounds rounds")
