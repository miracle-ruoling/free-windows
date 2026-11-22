# The sticker's two follow-ups (user, 2026-11-23): a 鐜荤拑 page when it really has a glass layer,
# and edge resizing.
#
#   .\t_deco2.ps1
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class D2 {
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
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() == cls) { f = h; return false; } return true; }, IntPtr.Zero);
    return f;
  }
  public static string Get(string s, string k, string d, string f) {
    var b = new StringBuilder(128); GetPrivateProfileStringW(s, k, d, b, 128, f); return b.ToString();
  }
  public static bool Set(string s, string k, string v, string f) { return WritePrivateProfileStringW(s, k, v, f); }
}
"@
[void][D2]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$pass = 0; $fail = 0
function Check($n, $c, $d) {
    if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
    else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) }
}
function Strip { return [D2]::Find('DockStripWindow') }
function Deco { return [D2]::Find('DockDecoWindow') }
function RectOf([IntPtr]$h) { $r = New-Object D2+RECT; [void][D2]::GetWindowRect($h, [ref]$r); return $r }
function Reload {
    $h = Strip
    if ($h -ne [IntPtr]::Zero) { [void][D2]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
    Start-Sleep -Milliseconds 1000
}
$orig = @{ enabled = [D2]::Get('deco', 'enabled', $null, $ini)
           bgMode = [D2]::Get('deco', 'bgMode', $null, $ini)
           glassLayer = [D2]::Get('deco', 'glassLayer', $null, $ini) }
try {
    [void][D2]::Set('deco', 'enabled', '1', $ini)
    [void][D2]::Set('deco', 'bgMode', '0', $ini)          # 閫忚繃鑳屽悗 + 鐜荤拑灞?=> it really bakes
    [void][D2]::Set('deco', 'glassLayer', '1', $ini)
    [void][D2]::Set('deco', 'x', '300', $ini)
    [void][D2]::Set('deco', 'y', '300', $ini)
    [void][D2]::Set('deco', 'w', '400', $ini)
    [void][D2]::Set('deco', 'h', '240', $ini)
    Reload
    $d = Deco
    if ($d -eq [IntPtr]::Zero) { throw 'sticker was not created' }

    # ---- 1. the 鐜荤拑 page exists (read its own tab list from the log) --------------
    $mark = (Get-Content $log).Count
    $r0 = RectOf $d
    $mx = [int](($r0.Left + $r0.Right) / 2)
    $my = [int](($r0.Top + $r0.Bottom) / 2)
    [void][D2]::SetCursorPos($mx, $my)
    Start-Sleep -Milliseconds 200
    [void][D2]::PostMessage($d, 0x0205, [IntPtr]0, [IntPtr]0)          # WM_RBUTTONUP -> its menu
    Start-Sleep -Milliseconds 600
    [void][D2]::SetCursorPos($mx + 60, $my + 14)                       # the first item: 璁剧疆...
    Start-Sleep -Milliseconds 150
    [D2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [D2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 900
    $line = Get-Content $log -Encoding UTF8 | Select-Object -Skip $mark |
            Where-Object { $_ -match 'settings: obj=3' } | Select-Object -Last 1
    Write-Output "== 1. page set =="
    Check "1  two tabs (the glass one included)" ($line -and $line -match '2 page') ($(if ($line) { $line.Trim() } else { 'none' }))
    $sw = [D2]::Find('DockSettingsWindow')
    if ($sw -ne [IntPtr]::Zero) { [void][D2]::PostMessage($sw, 0x0010, [IntPtr]0, [IntPtr]0) }
    Start-Sleep -Milliseconds 400

    # ---- 2. edge resize (posted messages: the sticker is behind other windows) -----
    $r1 = RectOf $d
    $cx = $r1.Right - 3
    $cy = $r1.Bottom - 3
    [void][D2]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 200
    [void][D2]::PostMessage($d, 0x0201, [IntPtr]1, [IntPtr]0)          # WM_LBUTTONDOWN
    Start-Sleep -Milliseconds 150
    [void][D2]::SetCursorPos($cx + 70, $cy + 40); Start-Sleep -Milliseconds 150
    [void][D2]::PostMessage($d, 0x0200, [IntPtr]0, [IntPtr]0)          # WM_MOUSEMOVE
    Start-Sleep -Milliseconds 250
    [void][D2]::PostMessage($d, 0x0202, [IntPtr]0, [IntPtr]0)          # WM_LBUTTONUP
    Start-Sleep -Milliseconds 400
    $r2 = RectOf $d
    Write-Output ""
    Write-Output "== 2. resize =="
    Write-Output ("  before " + ($r1.Right - $r1.Left) + "x" + ($r1.Bottom - $r1.Top) +
                  "  after " + ($r2.Right - $r2.Left) + "x" + ($r2.Bottom - $r2.Top) +
                  "  ini w=" + [D2]::Get('deco', 'w', '?', $ini) + " h=" + [D2]::Get('deco', 'h', '?', $ini))
    Check "2  the sticker grew by the drag" (($r2.Right - $r2.Left) -eq ($r1.Right - $r1.Left) + 70) ("w " + ($r1.Right - $r1.Left) + " -> " + ($r2.Right - $r2.Left))
    Check "3  and the new size was persisted" ([D2]::Get('deco', 'w', '0', $ini) -eq "$($r2.Right - $r2.Left)") ("ini w=" + [D2]::Get('deco', 'w', '?', $ini))
}
finally {
    [void][D2]::Set('deco', 'enabled', $orig.enabled, $ini)
    [void][D2]::Set('deco', 'bgMode', $orig.bgMode, $ini)
    [void][D2]::Set('deco', 'glassLayer', $orig.glassLayer, $ini)
    Reload
    Write-Output ""
    Write-Output ("  restored enabled='" + [D2]::Get('deco', 'enabled', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
