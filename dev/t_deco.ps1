# Task 5 acceptance: the desktop sticker.
#   * it exists only while [deco] enabled=1
#   * it sits at the bottom of the normal band: no WS_EX_TOPMOST, z index exactly one above Progman
#   * its geometry comes from [deco] x/y/w/h
#
#   .\t_deco.ps1
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class DC {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetPrivateProfileStringW(string s, string k, string d, StringBuilder b, int n, string f);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool WritePrivateProfileStringW(string s, string k, string v, string f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    IntPtr f = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() == cls) { f = h; return false; } return true; }, IntPtr.Zero);
    return f;
  }
  public static int Index(IntPtr want) {
    int idx = 0;
    for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero; h = GetWindow(h, 2), idx++)
      if (h == want) return idx;
    return -1;
  }
  public static bool Topmost(IntPtr h) { return ((long)GetWindowLong(h, -20) & 0x8L) != 0; }
  public static string Get(string s, string k, string d, string f) {
    var b = new StringBuilder(128); GetPrivateProfileStringW(s, k, d, b, 128, f); return b.ToString();
  }
  public static bool Set(string s, string k, string v, string f) { return WritePrivateProfileStringW(s, k, v, f); }
}
"@
[void][DC]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [DC]::Find('DockStripWindow') }
function Deco { return [DC]::Find('DockDecoWindow') }
function Reload { $h = Strip; if ($h -ne [IntPtr]::Zero) { [void][DC]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
                  Start-Sleep -Milliseconds 1000 }
$orig = @{ enabled = [DC]::Get('deco', 'enabled', $null, $ini)
           x = [DC]::Get('deco', 'x', $null, $ini)
           y = [DC]::Get('deco', 'y', $null, $ini)
           w = [DC]::Get('deco', 'w', $null, $ini)
           h = [DC]::Get('deco', 'h', $null, $ini) }
try {
    [void][DC]::Set('deco', 'enabled', '1', $ini)
    [void][DC]::Set('deco', 'x', '260', $ini)
    [void][DC]::Set('deco', 'y', '420', $ini)
    [void][DC]::Set('deco', 'w', '420', $ini)
    [void][DC]::Set('deco', 'h', '260', $ini)
    Reload
    $d = Deco
    Write-Output ("== enabled ==")
    if ($d -eq [IntPtr]::Zero) { Write-Output "  (no DockDecoWindow)"; throw 'sticker was not created' }
    $r = New-Object DC+RECT; [void][DC]::GetWindowRect($d, [ref]$r)
    $p = [DC]::Find('Progman')
    Write-Output ("  deco " + $r.Left + "," + $r.Top + " " + ($r.Right - $r.Left) + "x" + ($r.Bottom - $r.Top) +
                  "   z#" + [DC]::Index($d) + " topmost=" + [DC]::Topmost($d) +
                  "   strip z#" + [DC]::Index((Strip)) + "   Progman z#" + [DC]::Index($p))
    Check "1  the sticker exists and is visible" ($r.Left -eq 260 -and $r.Top -eq 420 -and $r.Right -eq 680 -and $r.Bottom -eq 680) ("rect " + $r.Left + "," + $r.Top)
    Check "2  it is not topmost" (-not [DC]::Topmost($d)) ("topmost=" + [DC]::Topmost($d))
    Check "3  it sits directly above the desktop window" ([DC]::Index($d) -eq ([DC]::Index($p) - 1)) ("deco z#" + [DC]::Index($d) + " progman z#" + [DC]::Index($p))
    # an app window covers it: that is the whole point of the bottom band
    $at = New-Object DC+POINT; $at.X = 470; $at.Y = 560
    $under = [DC]::GetAncestor([DC]::WindowFromPoint($at), 2)
    Write-Output ("  WindowFromPoint(470,560) = " + $under + "  (deco is " + $d + ", so an app window is above it: " + ($under -ne $d) + ")")
    $tail = Get-Content $log -Tail 40 | Where-Object { $_ -match 'deco: ' }
    Write-Output ("  log: " + (($tail | Select-Object -Last 2) -join ' | '))
    Check "4  its creation was logged" ($tail.Count -gt 0) ("lines: " + $tail.Count)

    Write-Output ""
    Write-Output "== disabled =="
    [void][DC]::Set('deco', 'enabled', '0', $ini)
    Reload
    Check "5  the window is gone" ((Deco) -eq [IntPtr]::Zero) ("found=" + (Deco))
}
finally {
    [void][DC]::Set('deco', 'enabled', $orig.enabled, $ini)
    Reload
    Write-Output ""
    Write-Output ("  restored enabled='" + [DC]::Get('deco', 'enabled', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
