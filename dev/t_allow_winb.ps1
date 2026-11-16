# Write an explicit "the taskbar may expand" request (allow) into the control block, then
# try Win+B. Tells us whether the mod's permission is what blocks the tray focus.
param([int]$AllowMs = 20000, [switch]$DenyInstead)
Add-Type -Language CSharp @"
using System; using System.IO.MemoryMappedFiles; using System.Runtime.InteropServices; using System.Text;
public class AL {
  [StructLayout(LayoutKind.Sequential)]
  public struct Blk { public uint magic, version, cloakUntilMs, pad, extMagic, extVersion, allowUntilMs, denyUntilMs; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Write(uint allow, uint deny, uint cloak) {
    using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.ReadWrite))
    using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.ReadWrite)) {
      Blk b; acc.Read(0, out b); b.allowUntilMs = allow; b.denyUntilMs = deny; b.cloakUntilMs = cloak; acc.Write(0, ref b); } }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl; }
  public static string Fg() { IntPtr h = GetForegroundWindow(); var b = new StringBuilder(200); GetClassName(h, b, 200);
    return "fg='" + b + "' tray=" + (h == FindWindow("Shell_TrayWnd", null)); }
  public static void WinB() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
  public static bool WaitTray(int ms) {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) { if (GetForegroundWindow() == FindWindow("Shell_TrayWnd", null)) return true; System.Threading.Thread.Sleep(10); }
    return false; }
}
"@
[void][AL]::SetProcessDpiAwarenessContext([IntPtr](-4))
$now = [Environment]::TickCount
Write-Output ("before: " + [AL]::Bar() + "  " + [AL]::Fg())
if ($DenyInstead) { [AL]::Write(0, [uint32]($now + $AllowMs), 0); Write-Output "wrote DENY" }
else { [AL]::Write([uint32]($now + $AllowMs), 0, 0); Write-Output "wrote ALLOW" }
Start-Sleep -Milliseconds 200
Write-Output ("after write: " + [AL]::Bar())
[AL]::WinB()
$got = [AL]::WaitTray(700)
Write-Output ("winb: focus arrived=" + $got + "  " + [AL]::Bar() + "  " + [AL]::Fg())
Start-Sleep -Milliseconds 400
Write-Output ("+0.4 s:      " + [AL]::Bar() + "  " + [AL]::Fg())
[AL]::Write(0, 0, 0)
Write-Output "cleared"
