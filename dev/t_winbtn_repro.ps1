# Reproduce "the native taskbar pops out while clicking the Windows cell".
#
# Hypothesis under test (2026-11-17): the shell leaves its taskbar *expanded* (y=1020)
# after the tray flyout is used, and only the mod's DWM cloak keeps it invisible. The next
# Win press (i.e. the next right click on the Windows cell) uncloaks it, so an already
# expanded bar becomes visible - and the shell refuses to collapse it again, so it stays
# until the user clicks elsewhere. Therefore no amount of "revoking the expansion
# permission" helps: the bar was never re-expanded, it was only un-hidden.
#
# Refuses to report if the real user touched the mouse/keyboard meanwhile.
param([int]$Settle = 2600, [switch]$SkipClean)
Add-Type -Language CSharp @"
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class RP {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  public static uint Idle() { LASTINPUTINFO l = new LASTINPUTINFO(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l); return (uint)Environment.TickCount - l.dwTime; }
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
    return string.Format("y={0,-4} cloaked={1} vis={2}  {3}", r.Top, cl, IsWindowVisible(h),
        r.Top >= 1070 ? "HIDDEN" : (cl != 0 ? "expanded but invisible (cloaked)" : "VISIBLE ON SCREEN"));
  }
  // watch the bar for ms, return "minY maxY firstRiseMs"
  public static string WatchSync(int ms) {
    int y0 = -99999; IntPtr h = FindWindow("Shell_TrayWnd", null); RECT r0;
    if (h != IntPtr.Zero && GetWindowRect(h, out r0)) y0 = r0.Top;
    int minY = 99999, maxY = -99999, rise = -1;
    var sw = Stopwatch.StartNew();
    while (sw.ElapsedMilliseconds < ms) {
      h = FindWindow("Shell_TrayWnd", null);
      if (h != IntPtr.Zero) { RECT r; if (GetWindowRect(h, out r)) { if (r.Top < minY) minY = r.Top; if (r.Top > maxY) maxY = r.Top; if (rise < 0 && y0 > -90000 && r.Top < y0 - 4) rise = (int)sw.ElapsedMilliseconds; } }
      Thread.Sleep(8);
    }
    return string.Format("y0={0} minY={1} maxY={2} riseAt={3}ms", y0, minY, maxY, rise);
  }
  public static void Click(uint down, uint up, int x, int y) {
    SetCursorPos(x, y); Thread.Sleep(25);
    mouse_event(down, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(45);
    mouse_event(up, 0, 0, 0, UIntPtr.Zero); }
  public static void Tap(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); Thread.Sleep(60); keybd_event(vk, 0, 2, UIntPtr.Zero); }
  public static void HidePost() { PostMessage(FindWindow("Shell_TrayWnd", null), 0x0113, (IntPtr)2, IntPtr.Zero); }
  public static void Chevron(IntPtr strip, int cx, int cy) {
    IntPtr lp = (IntPtr)(((long)cy << 16) | (uint)cx);
    PostMessage(strip, 0x0201, (IntPtr)1, lp); Thread.Sleep(60);
    PostMessage(strip, 0x0202, (IntPtr)0, lp); }
  // click in a worker thread while the bar is watched
  public static string RightThenLeft(int x, int y, int gap, int watch) {
    var t = new Thread(delegate() { Click(0x0008, 0x0010, x, y); Thread.Sleep(gap); Click(0x0002, 0x0004, x, y); });
    t.IsBackground = true; t.Start();
    string s = WatchSync(watch); t.Join(); return s; }
  public static string RightOnly(int x, int y, int watch) {
    var t = new Thread(delegate() { Click(0x0008, 0x0010, x, y); });
    t.IsBackground = true; t.Start();
    string s = WatchSync(watch); t.Join(); return s; }
}
"@
[void][RP]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$script:bad = $false
function Step([string]$tag) {
    $idle = [RP]::Idle()
    Write-Output ("{0,-46} {1}   [user idle {2} ms]" -f $tag, [RP]::Bar(), $idle)
    if ($idle -lt 1500) { $script:bad = $true }
}
function Now { (Get-Date).ToString("HH:mm:ss.fff") + "  " }

$strip = [RP]::Find("DockStripWindow")
$sr = New-Object RP+RECT
[void][RP]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path $log -Pattern "layout: " | Select-Object -Last 1).Line
if ($line -notmatch "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { Write-Output "cannot parse layout"; exit 1 }
$wx = $sr.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$wy = $sr.Top  + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
if ($line -notmatch "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { Write-Output "cannot parse chevron"; exit 1 }
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("win cell " + $wx + "," + $wy + "   chevron " + $cx + "," + $cy)

if (-not $SkipClean) {
    Write-Output "== A. clean state: right click, then left click (no tray involved) =="
    Step "A0 start"
    Write-Output ("A1 " + [RP]::RightThenLeft($wx, $wy, 250, 2200))
    Step "A2 after the pair"
    [RP]::Tap(0x1B); Start-Sleep -Milliseconds 300
}

Write-Output "== B. use the tray flyout once, then look at the bar =="
Step "B0 before the flyout"
[RP]::Chevron($strip, $cx, $cy)
Start-Sleep -Milliseconds $Settle
Step "B1 flyout opened"
[RP]::Chevron($strip, $cx, $cy)
Start-Sleep -Milliseconds $Settle
Step "B2 flyout closed"
Start-Sleep -Milliseconds 1500
Step "B3 +1.5 s"
[RP]::HidePost()
Start-Sleep -Milliseconds 900
Step "B4 asked the shell to hide (WM_TIMER 2)"
Start-Sleep -Milliseconds 1200
Step "B5 +1.2 s"

Write-Output "== C. one right click (a Win press) on the Windows cell =="
Write-Output ("C1 " + [RP]::RightOnly($wx, $wy, 1600))
Step "C2 after the right click"
Start-Sleep -Milliseconds 1500
Step "C3 +1.5 s"
[RP]::Tap(0x1B)
Write-Output "--- dock log ---"
Get-Content $log -Tail 100 | Select-String -Pattern "tray:|win button|panel: place|falling back|un-cloak" |
    Select-Object -Last 16 | ForEach-Object { $_.Line }
if ($script:bad) { Write-Output "!! the real user was active during this run - numbers are unreliable" }
else { Write-Output "clean run (nobody else touched the machine)" }

