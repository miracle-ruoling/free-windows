# Is Win+B's unreliability an artifact of keybd_event without scan codes?
# Sends Win+B with real scan codes (LWIN 0x5B, B 0x30) and reports how often the tray gets
# the keyboard focus, then the same with scan code 0.
param([int]$Rounds = 5, [switch]$NoScan)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class SC {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found; }
  public static string Fg() { IntPtr h = GetForegroundWindow(); var b = new StringBuilder(200); GetClassName(h, b, 200); return b.ToString(); }
  public static bool Tray() { return GetForegroundWindow() == FindWindow("Shell_TrayWnd", null); }
  public static string Fly() { IntPtr f = Find("TopLevelWindowForOverflowXamlIsland");
    if (f == IntPtr.Zero) return "none"; return IsWindowVisible(f) ? "visible" : "hidden"; }
  public static void WinB(bool scan) {
    byte sWin = scan ? (byte)0x5B : (byte)0;
    byte sB   = scan ? (byte)0x30 : (byte)0;
    keybd_event(0x5B, sWin, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42, sB, 0, UIntPtr.Zero);   System.Threading.Thread.Sleep(40);
    keybd_event(0x42, sB, 2, UIntPtr.Zero);   System.Threading.Thread.Sleep(40);
    keybd_event(0x5B, sWin, 2, UIntPtr.Zero); }
  public static int WaitTray(int ms) {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) { if (Tray()) return (int)sw.ElapsedMilliseconds; System.Threading.Thread.Sleep(10); }
    return -1; }
  public static void Tap(byte vk, byte sc) { keybd_event(vk, sc, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(50); keybd_event(vk, sc, 2, UIntPtr.Zero); }
}
"@
[void][SC]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ok = 0
for ($i = 1; $i -le $Rounds; $i++) {
    [SC]::WinB(-not $NoScan)
    $ms = [SC]::WaitTray(600)
    if ($ms -ge 0) { $ok++ }
    Write-Output ("round {0}: focus=tray after {1} ms   fg='{2}'" -f $i, $ms, [SC]::Fg())
    Start-Sleep -Milliseconds 700
    [SC]::Tap(0x1B, 0x01)      # Esc: drop the tray focus again
    Start-Sleep -Milliseconds 500
}
Write-Output ("focus arrived in {0} / {1} rounds (scanCode={2})" -f $ok, $Rounds, (-not $NoScan))
