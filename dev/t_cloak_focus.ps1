# Does a *cloaked* taskbar still take the keyboard focus from Win+B?
#   1. uncloaked: Win+B -> who owns the foreground?
#   2. cloaked (requested through the mod's own control block): Win+B -> same?
param([int]$DenyMs = 0)
Add-Type -Language CSharp @"
using System; using System.IO.MemoryMappedFiles; using System.Runtime.InteropServices; using System.Text;
public class CK {
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
  public static void Write(uint cloak, uint deny) {
    using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.ReadWrite))
    using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.ReadWrite)) {
      Blk b; acc.Read(0, out b); b.allowUntilMs = 0; b.denyUntilMs = deny; b.cloakUntilMs = cloak; acc.Write(0, ref b); } }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl; }
  public static string Fg() { IntPtr h = GetForegroundWindow(); var b = new StringBuilder(200); GetClassName(h, b, 200); return "fg='" + b + "' tray=" + (h == FindWindow("Shell_TrayWnd", null)); }
  public static void WinB() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
}
"@
[void][CK]::SetProcessDpiAwarenessContext([IntPtr](-4))
$now = [Environment]::TickCount
Write-Output ("before:        " + [CK]::Bar() + "  " + [CK]::Fg())
[CK]::Write(0, 0)
Start-Sleep -Milliseconds 200
Write-Output "== uncloaked: Win+B =="
[CK]::WinB(); Start-Sleep -Milliseconds 500
Write-Output ("  after winb:  " + [CK]::Bar() + "  " + [CK]::Fg())
Start-Sleep -Milliseconds 800
[CK]::Write([uint32]($now + 20000), 0)
Start-Sleep -Milliseconds 400
Write-Output ("== cloak requested, now: " + [CK]::Bar() + " ==")
Write-Output "== cloaked: Win+B =="
[CK]::WinB(); Start-Sleep -Milliseconds 500
Write-Output ("  after winb:  " + [CK]::Bar() + "  " + [CK]::Fg())
Start-Sleep -Milliseconds 500
Write-Output ("  +0.5 s:      " + [CK]::Bar() + "  " + [CK]::Fg())
[CK]::Write(0, 0)
Write-Output "cloak cleared (the mod should release it and ask the bar to hide)"
Start-Sleep -Milliseconds 1500
Write-Output ("end:           " + [CK]::Bar())
