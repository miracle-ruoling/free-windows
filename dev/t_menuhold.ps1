# Task 4 follow-up: while our own context menu is open, the group must not fold up - the trip
# from the window to a menu item leaves the "pointer is on the group" area, and that used to hide
# the group out from under the panel the menu was about to open (user, 2026-11-22).
#
#   .\t_menuhold.ps1
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class MH {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetPrivateProfileStringW(string s, string k, string d, StringBuilder b, int n, string f);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool WritePrivateProfileStringW(string s, string k, string v, string f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr f = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { f = h; return false; } return true; }, IntPtr.Zero);
    return f;
  }
  public static string Get(string s, string k, string d, string f) {
    var b = new StringBuilder(128); GetPrivateProfileStringW(s, k, d, b, 128, f); return b.ToString();
  }
  public static bool Set(string s, string k, string v, string f) { return WritePrivateProfileStringW(s, k, v, f); }
}
"@
[void][MH]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [MH]::Find('DockStripWindow') }
function RectOf([IntPtr]$h) { $r = New-Object MH+RECT; [void][MH]::GetWindowRect($h, [ref]$r); return $r }
function Restart { Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
                   Start-Process $exe; Start-Sleep -Seconds 2 }
function RightClick($x, $y) {
    [void][MH]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 120
    [MH]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [MH]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
}
function CloseMenu {
    # TrackPopupMenu ends on WM_CANCELMODE; a synthetic ESC is not delivered to its own loop
    $h = Strip
    if ($h -ne [IntPtr]::Zero) { [void][MH]::PostMessage($h, 0x001F, [IntPtr]0, [IntPtr]0) }
    Start-Sleep -Milliseconds 500
}
$orig = @{ hideEdge = [MH]::Get('group', 'hideEdge', $null, $ini) }
try {
    [void][MH]::Set('group', 'hideEdge', '1', $ini)
    Restart
    $s = RectOf (Strip)
    $awake = "$($s.Left),$($s.Top)"
    $cx = [int](($s.Left + $s.Right) / 2); $cy = [int](($s.Top + $s.Bottom) / 2)
    [void][MH]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 700
    Write-Output ("strip awake at " + $awake)

    Write-Output ""
    Write-Output "== right click on the strip, then walk the pointer far away =="
    RightClick $cx $cy
    Start-Sleep -Milliseconds 500
    [void][MH]::SetCursorPos(300, 800)          # way outside the group
    Start-Sleep -Milliseconds 1600
    $s2 = RectOf (Strip)
    Write-Output ("  strip now " + $s2.Left + "," + $s2.Top + "   (menu is open)")
    Check "1  an open context menu keeps the group on screen" ("$($s2.Left),$($s2.Top)" -eq $awake) ("$($s2.Left),$($s2.Top) vs " + $awake)
    CloseMenu
    Start-Sleep -Milliseconds 900
    # the grace after the menu closes must be short, but it has to hide again afterwards
    Start-Sleep -Milliseconds 1600
    $s3 = RectOf (Strip)
    Write-Output ("  strip after the menu closed + 2.5 s away: " + $s3.Left + "," + $s3.Top)
    Check "2  and it hides again once the menu is gone" ($s3.Top -lt ($s.Top - 40)) ("top=" + $s3.Top)
}
finally {
    CloseMenu
    [void][MH]::Set('group', 'hideEdge', $orig.hideEdge, $ini)
    Restart
    Write-Output ""
    Write-Output ("  restored hideEdge='" + [MH]::Get('group', 'hideEdge', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }

