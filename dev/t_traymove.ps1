# Can we click the *real* notification-area icon instead of forwarding messages?
#
# Step 1 (always): print the taskbar rect and every tray button UIA exposes with its screen
# rect, so we know which icons actually live in the taskbar (vs. the overflow flyout).
# Step 2 (-Move): move Shell_TrayWnd so the named icon lands at -At, then send a REAL left
# click there (SendInput) and report what happened. -Restore puts the taskbar back.
#
#   dev\t_traymove.ps1                          # list only
#   dev\t_traymove.ps1 -Name windhawk -Move -At 900,600
param(
    [string]$Name = "",
    [switch]$Move,
    [string]$At = "900,600",
    [switch]$Restore,
    [int]$Clicks = 1
)
Add-Type -Language CSharp @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class TR {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  public delegate bool EnumProc(IntPtr h, IntPtr lp);

  public static IntPtr Tray() { return FindWindow("Shell_TrayWnd", null); }
  public static string Rect(IntPtr h) { RECT r; if (!GetWindowRect(h, out r)) return "(no rect)"; return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top); }
  public static int RectLeft(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.Left; }
  public static int RectTop(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.Top; }
  public static bool Move(IntPtr h, int x, int y) {
    // SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSENDCHANGING
    return SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010 | 0x0400);
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(120);
    INPUT[] down = new INPUT[1];
    down[0].type = 0;
    down[0].mi.dwFlags = 0x0002;           // LEFTDOWN
    INPUT[] up = new INPUT[1];
    up[0].type = 0;
    up[0].mi.dwFlags = 0x0004;             // LEFTUP
    SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(60);
    SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
  }
  public static string Fg() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    StringBuilder t = new StringBuilder(100); GetWindowText(h, t, 100);
    return b.ToString() + " '" + t + "'";
  }
  public static List<string> VisibleWindows() {
    List<string> l = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      StringBuilder t = new StringBuilder(100); GetWindowText(h, t, 100);
      string s = (b.ToString() + "|" + t.ToString()).ToLower();
      if (s.IndexOf("windhawk") >= 0 || s.IndexOf("workbuddy") >= 0)
        l.Add(b.ToString() + " '" + t + "'");
      return true; }, IntPtr.Zero);
    return l;
  }
}
'@
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
[void][TR]::SetProcessDpiAwarenessContext([IntPtr](-4))

$tray = [TR]::Tray()
Write-Output ("Shell_TrayWnd = " + $tray.ToInt64() + "  rect=" + [TR]::Rect($tray))
if ($tray -eq [IntPtr]::Zero) { exit 1 }

$root = [System.Windows.Automation.AutomationElement]::FromHandle($tray)
$cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Button)
$buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
Write-Output ("UIA buttons under the taskbar: " + $buttons.Count)
$found = $null
foreach ($b in $buttons) {
    $r = $b.Current.BoundingRectangle
    $nm = $b.Current.Name
    if ($nm.Length -gt 42) { $nm = $nm.Substring(0, 42) }
    $mark = ""
    if ($Name -and $b.Current.Name.ToLower().Contains($Name.ToLower())) { $mark = "   <== match"; $found = $b }
    Write-Output ("   '" + $nm + "'  rect=" + [int]$r.X + "," + [int]$r.Y + " " + [int]$r.Width + "x" + [int]$r.Height + $mark)
}

if ($Restore) {
    [void][TR]::Move($tray, 0, 1028)
    Write-Output ("restored: " + [TR]::Rect($tray))
    exit 0
}

if ($Move) {
    if (-not $found) { Write-Output ("no button matches '" + $Name + "'"); exit 1 }
    $r = $found.Current.BoundingRectangle
    $tb = New-Object TR+RECT
    [void][TR]::GetWindowRect($tray, [ref]$tb)
    # where the icon sits inside the taskbar
    $ox = [int]($r.X - $tb.Left + $r.Width / 2)
    $oy = [int]($r.Y - $tb.Top + $r.Height / 2)
    Write-Output ("icon offset inside the taskbar: " + $ox + "," + $oy)
    $parts = $At.Split(',')
    $tx = [int]$parts[0] - $ox
    $ty = [int]$parts[1] - $oy
    Write-Output ("moving the taskbar to " + $tx + "," + $ty + " so the icon lands at " + $At)
    [void][TR]::Move($tray, $tx, $ty)
    Start-Sleep -Milliseconds 250
    Write-Output ("taskbar now " + [TR]::Rect($tray))
    $r2 = $found.Current.BoundingRectangle
    Write-Output ("icon now " + [int]$r2.X + "," + [int]$r2.Y + " " + [int]$r2.Width + "x" + [int]$r2.Height)
    Write-Output ("fg before click: " + [TR]::Fg())
    for ($i = 0; $i -lt $Clicks; $i++) {
        [TR]::Click([int]$parts[0], [int]$parts[1])
        Start-Sleep -Milliseconds 180
    }
    Start-Sleep -Milliseconds 1200
    Write-Output ("fg after click : " + [TR]::Fg())
    Write-Output ("windows of interest: " + (([TR]::VisibleWindows()) -join " | "))
    [void][TR]::Move($tray, 0, 1078)     # back off screen (the taskbar mod's own hidden position)
    Start-Sleep -Milliseconds 300
    Write-Output ("taskbar put back: " + [TR]::Rect($tray))
}
