# Write a "keep the taskbar down" request into the shared block ourselves, then press Win:
# the mod must refuse to expand while that request lives. Isolates "does the mod read the
# block at all?" from anything the dock does.
param([int]$DenyMs = 8000)
Add-Type -Language CSharp @"
using System; using System.IO.MemoryMappedFiles; using System.Runtime.InteropServices;
public class DT {
  [StructLayout(LayoutKind.Sequential)]
  public struct Blk { public uint magic, version, cloakUntilMs, pad, extMagic, extVersion, allowUntilMs, denyUntilMs; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static Blk Read() {
    using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.Read))
    using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.Read)) {
      Blk b; acc.Read(0, out b); return b; } }
  public static void Write(uint allow, uint deny, uint cloak) {
    using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.ReadWrite))
    using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.ReadWrite)) {
      Blk b; acc.Read(0, out b);
      b.allowUntilMs = allow; b.denyUntilMs = deny; b.cloakUntilMs = cloak;
      acc.Write(0, ref b); } }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? "  HIDDEN" : "  ON SCREEN"); }
  public static void Tap(byte vk) { keybd_event(vk,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk,0,2,UIntPtr.Zero); }
}
"@
[void][DT]::SetProcessDpiAwarenessContext([IntPtr](-4))
$b = [DT]::Read()
$now = [Environment]::TickCount
Write-Output ("before: magic=0x{0:X8} ext=0x{1:X8}/{2} allow={3} deny={4} cloak={5}" -f $b.magic, $b.extMagic, $b.extVersion, [int]$b.allowUntilMs - $now, [int]$b.denyUntilMs - $now, [int]$b.cloakUntilMs - $now)
Write-Output ("bar: " + [DT]::Bar())
[DT]::Write(0, [uint32]($now + $DenyMs), 0)
Write-Output ("wrote deny=+" + $DenyMs + " ms; block now: " + (([DT]::Read().denyUntilMs - $now)) + " ms")
Start-Sleep -Milliseconds 300
Write-Output "--- Win tap while deny is live (the bar must NOT rise) ---"
[DT]::Tap(0x5B)
Start-Sleep -Milliseconds 2500
Write-Output ("after win: " + [DT]::Bar())
[DT]::Tap(0x1B)
Start-Sleep -Milliseconds 800
Write-Output ("after esc: " + [DT]::Bar())
[DT]::Write(0, 0, 0)
Write-Output "deny cleared"
