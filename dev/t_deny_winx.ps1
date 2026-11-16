# Does the deny request reach Win+X at all? Write the deny ourselves, wait, then send the
# same chord the dock sends (Win down / X / X up / Win up) and watch the bar.
param([int]$LeadMs = 400, [int]$DenyMs = 6000)
Add-Type -Language CSharp @"
using System; using System.IO.MemoryMappedFiles; using System.Runtime.InteropServices;
public class DX {
  [StructLayout(LayoutKind.Sequential)]
  public struct Blk { public uint magic, version, cloakUntilMs, pad, extMagic, extVersion, allowUntilMs, denyUntilMs; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Write(uint deny) {
    using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.ReadWrite))
    using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.ReadWrite)) {
      Blk b; acc.Read(0, out b); b.allowUntilMs = 0; b.denyUntilMs = deny; acc.Write(0, ref b); } }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? "  HIDDEN" : "  ON SCREEN"); }
  public static string Watch(int ms) {
    int minY = 99999, maxY = -99999; var sw = System.Diagnostics.Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) {
      IntPtr h = FindWindow("Shell_TrayWnd", null);
      if (h != IntPtr.Zero) { RECT r; if (GetWindowRect(h, out r)) { if (r.Top < minY) minY = r.Top; if (r.Top > maxY) maxY = r.Top; } }
      System.Threading.Thread.Sleep(8); }
    return "minY=" + minY + " maxY=" + maxY; }
  public static void WinX() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x58,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(20);
    keybd_event(0x58,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(20);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
}
"@
[void][DX]::SetProcessDpiAwarenessContext([IntPtr](-4))
$now = [Environment]::TickCount
Write-Output ("start bar: " + [DX]::Bar())
[DX]::Write([uint32]($now + $DenyMs))
Write-Output ("deny written (+" + $DenyMs + " ms), waiting " + $LeadMs + " ms so the mod's 20 ms cache can see it")
Start-Sleep -Milliseconds $LeadMs
Write-Output ("bar before chord: " + [DX]::Bar())
$t = New-Object System.Threading.Thread([System.Threading.ThreadStart]{ })
# watch in this thread, chord on a worker created in C#
[DX]::WinX()
Write-Output ("watching 2000 ms: " + [DX]::Watch(2000))
Write-Output ("after: " + [DX]::Bar())
[DX]::Write(0)
[void][DX]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class KBz { [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e); }
"@
[KBz]::keybd_event(0x1B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 40; [KBz]::keybd_event(0x1B,0,2,[UIntPtr]::Zero)
Write-Output "deny cleared, esc sent"
