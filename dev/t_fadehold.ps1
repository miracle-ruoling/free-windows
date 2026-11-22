# The distance fade must also hold still while our own menu is open (user, 2026-11-23: "根据距离
# 淡入淡出时也需要前往右键菜单时不淡出").
#
#   .\t_fadehold.ps1
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class FH {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
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
[void][FH]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [FH]::Find('DockStripWindow') }
function RectOf([IntPtr]$h) { $r = New-Object FH+RECT; [void][FH]::GetWindowRect($h, [ref]$r); return $r }
$orig = @{ hideMode = [FH]::Get('group', 'hideMode', $null, $ini) }
try {
    [void][FH]::Set('group', 'hideMode', '0', $ini)      # 距离淡出
    Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
    Start-Process $exe; Start-Sleep -Seconds 2
    $s = RectOf (Strip)
    $cx = [int](($s.Left + $s.Right) / 2); $cy = [int](($s.Top + $s.Bottom) / 2)
    [void][FH]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 600
    Write-Output ("strip " + $s.Left + "," + $s.Top)

    Write-Output ""
    Write-Output "== A. baseline: nothing of ours is open, the fade runs =="
    $mark0 = (Get-Content $log).Count
    [void][FH]::SetCursorPos(300, 800); Start-Sleep -Milliseconds 1200
    $base = @(Get-Content $log | Select-Object -Skip $mark0 | Where-Object { $_ -match 'fade: ' })
    Write-Output ("  fade lines: " + $base.Count)
    Check "A  距离淡出 works when nothing is open" ($base.Count -gt 0) ("lines: " + $base.Count)

    Write-Output ""
    Write-Output "== B. right click (our menu is up), then walk far away: no fade =="
    [void][FH]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 400
    [FH]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [FH]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    $mark = (Get-Content $log).Count
    [void][FH]::SetCursorPos(300, 800)
    Start-Sleep -Milliseconds 1600
    $during = @(Get-Content $log | Select-Object -Skip $mark | Where-Object { $_ -match 'fade: ' })
    Write-Output ("  fade lines while the menu was open: " + $during.Count)
    Check "B  no fade while our menu is open" ($during.Count -eq 0) ("lines: " + $during.Count)
}
finally {
    [void][FH]::Set('group', 'hideMode', $orig.hideMode, $ini)
    Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
    Start-Process $exe; Start-Sleep -Seconds 1
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
