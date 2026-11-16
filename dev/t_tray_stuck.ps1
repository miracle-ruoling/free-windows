# Does using the shell's tray flyout leave the native taskbar expanded-but-cloaked?
#
#   1. open the flyout with "^",  2. close it with "^",  3. ask the shell to hide the bar,
#   4. press Win (uncloak), 5. press Win again (hide).  The bar is printed after every step.
#
# Why it matters: while the bar sits expanded at y=1020 and only the mod's cloak keeps it
# invisible, the next Win press uncloaks it -> the taskbar appears and does not come back
# down by itself ("the taskbar pops out while I click the Windows button").
param([int]$Settle = 2500)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class TS {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found; }
  public static string Bar() {
    IntPtr h = FindWindow("Shell_TrayWnd", null);
    if (h == IntPtr.Zero) return "Shell_TrayWnd not found";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    return string.Format("y={0} {1}x{2} vis={3} cloaked={4}  (1078=hidden, 1020=expanded)",
        r.Top, r.Right - r.Left, r.Bottom - r.Top, IsWindowVisible(h), cl); }
  public static void Tap(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk, 0, 2, UIntPtr.Zero); }
  public static void HidePost() { PostMessage(FindWindow("Shell_TrayWnd", null), 0x0113, (IntPtr)2, IntPtr.Zero); }
}
"@
[void][TS]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [TS]::Find("DockStripWindow")
$sr = New-Object TS+RECT
[void][TS]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Pattern "layout: " |
         Select-Object -Last 1).Line
$line -match "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
$lp = [IntPtr]([int64]($cy -shl 16) -bor $cx)

function Step([string]$tag) { Write-Output ("{0,-34} {1}" -f $tag, [TS]::Bar()) }
function Chev {
    [void][TS]::PostMessage($strip, 0x0201, [IntPtr]1, $lp)
    Start-Sleep -Milliseconds 60
    [void][TS]::PostMessage($strip, 0x0202, [IntPtr]0, $lp)
}

Step "0. start"
Chev
Start-Sleep -Milliseconds $Settle
Step "1. flyout opened (^)"
Chev
Start-Sleep -Milliseconds $Settle
Step "2. flyout closed (^)"
[TS]::HidePost()
Start-Sleep -Milliseconds 900
Step "3. asked the shell to hide (WM_TIMER 2)"
Start-Sleep -Milliseconds 1200
Step "4. +1.2 s"
[TS]::Tap(0x5B)
Start-Sleep -Milliseconds 1200
Step "5. Win pressed (uncloak?)"
[TS]::Tap(0x5B)
Start-Sleep -Milliseconds 1500
Step "6. Win pressed again (hide?)"
[TS]::Tap(0x1B)
Write-Output "--- dock log ---"
Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 80 |
    Select-String -Pattern "tray:|win button|panel: place|falling back|un-cloak" |
    Select-Object -Last 14 | ForEach-Object { $_.Line }
