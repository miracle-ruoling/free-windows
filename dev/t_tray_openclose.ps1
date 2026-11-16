# The user's report: "tray opens -> taskbar disappears, tray closes -> taskbar appears and
# then never goes away again". Walk one full open/close round and report the bar + flyout at
# every step, then a click on empty desktop.
param([int]$Settle = 3500, [int]$OutX = 5, [int]$OutY = 540)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class TC2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
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
    if (h == IntPtr.Zero) return "bar: not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return "bar y=" + r.Top + " cloaked=" + cl + (r.Top >= 1070 ? " HIDDEN" : " VISIBLE"); }
  public static string Fly() {
    IntPtr f = Find("TopLevelWindowForOverflowXamlIsland");
    if (f == IntPtr.Zero) return "flyout none";
    RECT r; GetWindowRect(f, out r);
    return "flyout " + (IsWindowVisible(f) ? "visible" : "hidden") + " at " + r.Left + "," + r.Top; }
  public static void Chev(IntPtr strip, int cx, int cy) {
    IntPtr lp = (IntPtr)(((long)cy << 16) | (uint)cx);
    PostMessage(strip, 0x0201, (IntPtr)1, lp); System.Threading.Thread.Sleep(60);
    PostMessage(strip, 0x0202, (IntPtr)0, lp); }
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(60);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero); }
  public static void Tap(byte vk) { keybd_event(vk,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk,0,2,UIntPtr.Zero); }
  [DllImport("user32.dll")] public static extern void keybd_event(byte v, byte s, uint f, UIntPtr e);
}
"@
[void][TC2]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$strip = [TC2]::Find("DockStripWindow"); $sr = New-Object TC2+RECT
[void][TC2]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path $log -Pattern "layout: " | Select-Object -Last 1).Line
$line -match "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
function Step([string]$tag) { Write-Output ("{0,-28} {1}   {2}" -f $tag, [TC2]::Bar(), [TC2]::Fly()) }

Step "0. start"
Write-Output "--- normalise with Win (open Start, close Start) ---"
[TC2]::Tap(0x5B); Start-Sleep -Milliseconds 1200
[TC2]::Tap(0x5B); Start-Sleep -Milliseconds 1500
Step "1. after two Win taps"

Write-Output "--- click ^ (open the tray) ---"
[TC2]::Chev($strip, $cx, $cy)
Start-Sleep -Milliseconds $Settle
Step "2. tray opened"

Write-Output "--- click ^ again (close the tray) ---"
[TC2]::Chev($strip, $cx, $cy)
Start-Sleep -Milliseconds $Settle
Step "3. tray closed"

Write-Output "--- click on empty desktop ---"
[TC2]::Click($OutX, $OutY)
Start-Sleep -Milliseconds 1500
Step "4. after an outside click"
Start-Sleep -Milliseconds 1500
Step "5. +1.5 s"

Write-Output "--- dock log ---"
Get-Content $log -Tail 80 | Select-String -Pattern "tray:|taskbar ctl|win button|falling back|un-cloak" |
    Select-Object -Last 16 | ForEach-Object { $_.Line }
