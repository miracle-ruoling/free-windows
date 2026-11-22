# Task 4, part 2: a group with a *single* member (the 3-icon window alone) must work through the
# same group settings - no special case. Also: click mode, 鐢憡妯?band, and that group 1 is untouched.
#
#   .\t_hide2.ps1
param([int]$Settle = 1200)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class H2 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetPrivateProfileStringW(string s, string k, string d, StringBuilder b, int n, string f);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool WritePrivateProfileStringW(string s, string k, string v, string f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
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
  public static RECT Monitor(IntPtr h) {
    var mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(mi);
    GetMonitorInfo(MonitorFromWindow(h, 2), ref mi); return mi.rcMonitor;
  }
}
"@
[void][H2]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [H2]::Find('DockStripWindow') }
function Tray { return [H2]::Find('DockTrayBarWindow') }
function RectOf([IntPtr]$h) { $r = New-Object H2+RECT; [void][H2]::GetWindowRect($h, [ref]$r); return $r }
function RStr($r) { return "$($r.Left),$($r.Top) $($r.Right - $r.Left)x$($r.Bottom - $r.Top)" }
function Restart { Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
                   Start-Process $exe; Start-Sleep -Seconds 2 }
function LogTail([int]$n = 6) { Get-Content $log -Tail 200 | Where-Object { $_ -match 'hide: ' } | Select-Object -Last $n }

$orig = @{
    trayGroup = [H2]::Get('traybar', 'group', $null, $ini)
    g1hide = [H2]::Get('group', 'hideMode', $null, $ini)
    g2hide = [H2]::Get('group.2', 'hideMode', $null, $ini)
    g2ext = [H2]::Get('group.2', 'wakeExt', $null, $ini)
    g2vis = [H2]::Get('group.2', 'wakeVisible', $null, $ini)
    g2mode = [H2]::Get('group.2', 'wakeMode', $null, $ini)
    g2margin = [H2]::Get('group.2', 'margin', '8', $ini)
}
$mg2 = [int]$orig.g2margin
function Restore {
    [void][H2]::Set('group.2', 'hideMode', $orig.g2hide, $ini)
    [void][H2]::Set('group.2', 'wakeExt', $orig.g2ext, $ini)
    [void][H2]::Set('group.2', 'wakeVisible', $orig.g2vis, $ini)
    [void][H2]::Set('group.2', 'wakeMode', $orig.g2mode, $ini)
    [void][H2]::Set('group', 'hideMode', $orig.g1hide, $ini)
    [void][H2]::Set('traybar', 'group', $orig.trayGroup, $ini)
}
try {
    Write-Output ("before: [traybar] group='" + $orig.trayGroup + "'  [group.2] hideMode='" + $orig.g2hide + "'")
    $stripBefore = RectOf (Strip)
    # the 3-icon window gets its own group, and that group (one member) turns hiding on
    [void][H2]::Set('traybar', 'group', '2', $ini)
    [void][H2]::Set('group', 'hideMode', '0', $ini)
    [void][H2]::Set('group.2', 'hideMode', '1', $ini)
    [void][H2]::Set('group.2', 'wakeExt', '8', $ini)
    [void][H2]::Set('group.2', 'wakeVisible', '1', $ini)
    [void][H2]::Set('group.2', 'wakeMode', '0', $ini)      # click to wake
    Restart
    $h = Tray
    $mon = [H2]::Monitor($h)
    $c0 = RectOf $h
    # park the pointer on it so the arming grace does not expire while we look
    [void][H2]::SetCursorPos([int](($c0.Left + $c0.Right) / 2), [int](($c0.Top + $c0.Bottom) / 2))
    Start-Sleep -Milliseconds 500
    $c1 = RectOf (Tray)
    Write-Output ""
    Write-Output ("== single-member group glued:  tray " + (RStr $c1) + "  (bounds top should be " + ($mon.Top + 15) + ")")
    Write-Output ("  log: " + ((LogTail 3) -join ' | '))
    Check "1  one-member group glues itself (bounds 15 px inset)" (($c1.Top - $mg2) -eq ($mon.Top + 15)) ("bounds.top=" + ($c1.Top - $mg2))
    Check "1  and the strip (group 1, 距离 mode) was left alone" ((RectOf (Strip)).Top -eq [int][H2]::Get('dock', 'y', '0', $ini)) ("strip " + (RectOf (Strip)).Top + " vs ini y " + [H2]::Get('dock', 'y', '0', $ini))

    Write-Output ""
    Write-Output "== click on the band wakes it =="
    [void][H2]::SetCursorPos([int](($mon.Left + $mon.Right) / 2), [int](($mon.Top + $mon.Bottom) / 2))
    Start-Sleep -Milliseconds ($Settle + 300)
    $c2 = RectOf (Tray)
    Write-Output ("  hidden: tray " + (RStr $c2))
    Check "2  the single member slid out" (($c2.Bottom + $mg2) -le $mon.Top) ("bounds.bottom=" + ($c2.Bottom + $mg2))
    $w = [H2]::Find('DockWakeWindow')
    $wr = if ($w -ne [IntPtr]::Zero) { RectOf $w } else { $null }
    Write-Output ("  band " + $(if ($wr) { (RStr $wr) + " visible=" + [H2]::IsWindowVisible($w) } else { '(none)' }))
    Check "2  the band is painted (鐢憡妯? and 8 px thick" ($wr -and $wr.Bottom -eq ($mon.Top + 8) -and [H2]::IsWindowVisible($w)) $(if ($wr) { RStr $wr } else { '' })
    # a click only makes sense with the pointer on the band (with the pointer far away the group wakes
# and is "left" again at once, which is correct behaviour - just not what this checks)
[void][H2]::SetCursorPos([int](($wr.Left + $wr.Right) / 2), [int]($mon.Top + 4))
Start-Sleep -Milliseconds 300
[void][H2]::PostMessage($w, 0x0202, [IntPtr]0, [IntPtr]0)     # WM_LBUTTONUP -> wake
    Start-Sleep -Milliseconds ($Settle + 300)
    $c3 = RectOf (Tray)
    Write-Output ("  after the click: " + (RStr $c3))
    Write-Output ("  log: " + ((LogTail 2) -join ' | '))
    Check "3  a click on the band brings it back" (($c3.Top - $mg2) -eq ($mon.Top + 15)) ("bounds.top=" + ($c3.Top - $mg2))
}
finally {
    Write-Output ""
    Write-Output "== restoring =="
    Restore
    Restart
    Start-Sleep -Milliseconds 400
    Write-Output ("  tray " + (RStr (RectOf (Tray))) + "   strip " + (RStr (RectOf (Strip))))
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }


