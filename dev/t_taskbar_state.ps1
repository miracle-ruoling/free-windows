# Native taskbar state: rect / visible / cloaked, or ask the shell to hide it.
#   -Hide      post TrayUI's own hide timer (kTrayTimerHide = WM_TIMER 2) to the bar
#   -Watch N   poll for N ms and print every change
param([switch]$Hide, [int]$Watch = 0)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
using System.Diagnostics;
public class TB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static System.Collections.Generic.List<IntPtr> Bars = new System.Collections.Generic.List<IntPtr>();
  public static void Collect() {
    Bars.Clear();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      string c = b.ToString();
      if (c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") Bars.Add(h);
      return true; }, IntPtr.Zero); }
  public static string One(IntPtr h) {
    if (!IsWindow(h)) return "gone";
    RECT r; GetWindowRect(h, out r);
    int cl = 0; DwmGetWindowAttribute(h, 14, out cl, 4);
    int screenBottom = GetSystemMetrics(1);
    int vis = r.Bottom - r.Top; if (r.Top > 0) vis = (r.Bottom < screenBottom ? r.Bottom : screenBottom) - r.Top;
    return string.Format("{0} {1} rect={2},{3} {4}x{5} vis={6} cloaked={7} onScreen={8}px",
      h.ToString("X"), "", r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top,
      IsWindowVisible(h), cl, vis);
  }
  public static void HideAll() {
    Collect();
    foreach (IntPtr h in Bars) PostMessage(h, 0x0113, (IntPtr)2, IntPtr.Zero);
  }
}
"@
[void][TB]::SetProcessDpiAwarenessContext([IntPtr](-4))
if ($Hide) { [TB]::HideAll(); Start-Sleep -Milliseconds 600 }
[TB]::Collect()
if ($Watch -le 0) {
    foreach ($h in [TB]::Bars) { [TB]::One($h) }
    exit 0
}
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = ""
while ($sw.ElapsedMilliseconds -lt $Watch) {
    $cur = (@([TB]::Bars | ForEach-Object { [TB]::One($_) }) -join " | ")
    if ($cur -ne $last) { Write-Output ("{0,6} ms  {1}" -f $sw.ElapsedMilliseconds, $cur); $last = $cur }
    Start-Sleep -Milliseconds 10
}
