# Watch the shell's tray flyout windows and the taskbar while clicking "^" a few times.
# Prints every change of: bar y/cloak, each TopLevelWindowForOverflowXamlIsland window's
# visibility and rect. That is what tells us who closes the flyout ("gone" 1.3 s after it
# opened, with no click from the user).
param([int]$TotalMs = 14000, [int]$Clicks = 2, [int]$FirstClickAt = 1500, [int]$Gap = 4000)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class FW {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static string Cls(IntPtr h) { var b = new StringBuilder(200); GetClassName(h, b, 200); return b.ToString(); }

  public static string Snapshot() {
    var sb = new StringBuilder();
    IntPtr bar = FindWindow("Shell_TrayWnd", null);
    int cl = 0; RECT br = new RECT();
    if (bar != IntPtr.Zero && GetWindowRect(bar, out br)) DwmGetWindowAttribute(bar, 14, out cl, 4);
    sb.Append("bar y=" + br.Top + " cl=" + cl);
    var fly = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (Cls(h) != "TopLevelWindowForOverflowXamlIsland") return true;
      RECT r; GetWindowRect(h, out r);
      fly.Add("fly " + h.ToString("X") + " vis=" + IsWindowVisible(h) + " @" + r.Left + "," + r.Top);
      return true; }, IntPtr.Zero);
    sb.Append(fly.Count == 0 ? "  [no flyout window]" : "  [" + string.Join(" | ", fly.ToArray()) + "]");
    IntPtr fg = GetForegroundWindow();
    sb.Append("  fg=" + (fg == bar ? "BAR" : Cls(fg)));
    return sb.ToString();
  }
  public static void Chev(IntPtr strip, int cx, int cy) {
    IntPtr lp = (IntPtr)(((long)cy << 16) | (uint)cx);
    PostMessage(strip, 0x0201, (IntPtr)1, lp); Thread.Sleep(60);
    PostMessage(strip, 0x0202, (IntPtr)0, lp); }
  public static string Run(IntPtr strip, int cx, int cy, int totalMs, int clicks, int firstAt, int gap) {
    var sb = new StringBuilder();
    var sw = Stopwatch.StartNew();
    string last = "";
    int done = 0;
    while (sw.ElapsedMilliseconds < totalMs) {
      if (done < clicks && sw.ElapsedMilliseconds >= firstAt + done * gap) {
        Chev(strip, cx, cy);
        sb.AppendLine(sw.ElapsedMilliseconds + " ms  >>> clicked ^ (#" + (done + 1) + ")");
        done++;
      }
      string cur = Snapshot();
      if (cur != last) { sb.AppendLine(string.Format("{0,6} ms  {1}", sw.ElapsedMilliseconds, cur)); last = cur; }
      Thread.Sleep(15);
    }
    return sb.ToString();
  }
}
"@
[void][FW]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$strip = [IntPtr]::Zero
$sr = New-Object FW+RECT
[void][FW]::EnumWindows({ param($h,$l) $script:n = [FW]::Cls($h); if ($script:n -eq "DockStripWindow") { $script:strip = $h; return $false }; return $true }, [IntPtr]::Zero)
$strip = $script:strip
if ($strip -eq [IntPtr]::Zero) { Write-Output "no strip window"; exit 1 }
[void][FW]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path $log -Pattern "layout: " | Select-Object -Last 1).Line
$line -match "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output ("chevron " + $cx + "," + $cy + "   clicks=" + $Clicks + " gap=" + $Gap + " ms")
Write-Output ([FW]::Run($strip, $cx, $cy, $TotalMs, $Clicks, $FirstClickAt, $Gap))
