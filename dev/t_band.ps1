# Task 5 plumbing: [traybar] band 0 = the topmost band (as always), 1 = the bottom of the normal
# band (just above the desktop, below every app window).
#
#   .\t_band.ps1
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class BD {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetPrivateProfileStringW(string s, string k, string d, StringBuilder b, int n, string f);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool WritePrivateProfileStringW(string s, string k, string v, string f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
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
[void][BD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [BD]::Find('DockStripWindow') }
function Tray { return [BD]::Find('DockTrayBarWindow') }
function Reload { $h = Strip; if ($h -ne [IntPtr]::Zero) { [void][BD]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
                  Start-Sleep -Milliseconds 900 }
function Report([string]$tag) {
    $t = Tray; $s = Strip; $p = [BD]::Find('Progman')
    Write-Output ("  " + $tag + ": tray z#" + [BD]::Index($t) + " topmost=" + [BD]::Topmost($t) +
                  "   strip z#" + [BD]::Index($s) + " topmost=" + [BD]::Topmost($s) +
                  "   Progman z#" + [BD]::Index($p))
}
$orig = @{ band = [BD]::Get('traybar', 'band', $null, $ini) }
try {
    [void][BD]::Set('traybar', 'band', '0', $ini)
    Reload
    Write-Output "== band 0 (最上, the default) =="
    Report "after"
    Check "1  tray is topmost, above the strip and far above the desktop" (([BD]::Topmost((Tray))) -and ([BD]::Index((Tray)) -lt [BD]::Index((Strip)))) ("tray z#" + [BD]::Index((Tray)))

    [void][BD]::Set('traybar', 'band', '1', $ini)
    Reload
    Write-Output ""
    Write-Output "== band 1 (最下) =="
    Report "after"
    $t = Tray; $p = [BD]::Find('Progman')
    $ti = [BD]::Index($t); $pi = [BD]::Index($p)
    Check "2  tray lost WS_EX_TOPMOST" (-not [BD]::Topmost($t)) ("topmost=" + [BD]::Topmost($t))
    Check "3  and sits directly above the desktop window" ($ti -eq ($pi - 1)) ("tray z#" + $ti + " progman z#" + $pi)
    Check "4  the strip is untouched" ([BD]::Topmost((Strip))) ("strip topmost=" + [BD]::Topmost((Strip)))

    [void][BD]::Set('traybar', 'band', '0', $ini)
    Reload
    Write-Output ""
    Write-Output "== back to band 0 =="
    Report "after"
    Check "5  topmost again" ([BD]::Topmost((Tray))) ("topmost=" + [BD]::Topmost((Tray)))
}
finally {
    [void][BD]::Set('traybar', 'band', $orig.band, $ini)
    Reload
    Write-Output ""
    Write-Output ("  restored band='" + [BD]::Get('traybar', 'band', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
