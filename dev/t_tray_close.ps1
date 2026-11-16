# With the shell's tray flyout open, what closes it? Try, in order: plain Space, then
# Win+B followed by Space. Reports the flyout window and the foreground class each time.
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class CF {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found; }
  public static string Cls(IntPtr h) { if (h == IntPtr.Zero) return "0"; var b = new StringBuilder(200); GetClassName(h, b, 200); return b.ToString(); }
  public static string Fly() {
    IntPtr f = Find("TopLevelWindowForOverflowXamlIsland");
    if (f == IntPtr.Zero) return "flyout none";
    RECT r; GetWindowRect(f, out r);
    return "flyout vis=" + IsWindowVisible(f) + " at " + r.Left + "," + r.Top + " (parked=" + (r.Top > 1000) + ")"; }
  public static string Fg() { return "fg='" + Cls(GetForegroundWindow()) + "'"; }
  public static void Tap(byte vk) { keybd_event(vk,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(50); keybd_event(vk,0,2,UIntPtr.Zero); }
  public static void WinB() {
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x42,0,2,UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x5B,0,2,UIntPtr.Zero); }
  public static void Chev(IntPtr strip, int cx, int cy) {
    IntPtr lp = (IntPtr)(((long)cy << 16) | (uint)cx);
    PostMessage(strip, 0x0201, (IntPtr)1, lp); System.Threading.Thread.Sleep(60);
    PostMessage(strip, 0x0202, (IntPtr)0, lp); }
}
"@
[void][CF]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$strip = [CF]::Find("DockStripWindow"); $sr = New-Object CF+RECT
[void][CF]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path $log -Pattern "layout: " | Select-Object -Last 1).Line
$line -match "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("start:  " + [CF]::Fly() + "  " + [CF]::Fg())
Write-Output "opening the flyout with ^ ..."
[CF]::Chev($strip, $cx, $cy)
Start-Sleep -Milliseconds 3500
Write-Output ("open:   " + [CF]::Fly() + "  " + [CF]::Fg())
Write-Output "--- plain Space ---"
[CF]::Tap(0x20)
Start-Sleep -Milliseconds 1200
Write-Output ("after space:  " + [CF]::Fly() + "  " + [CF]::Fg())
Write-Output "--- Win+B then Space ---"
[CF]::WinB()
Start-Sleep -Milliseconds 250
Write-Output ("after winb:   " + [CF]::Fly() + "  " + [CF]::Fg())
[CF]::Tap(0x20)
Start-Sleep -Milliseconds 1200
Write-Output ("after winb+space: " + [CF]::Fly() + "  " + [CF]::Fg())
Get-Content $log -Tail 12 | Select-String -Pattern "tray:" | ForEach-Object { $_.Line }
