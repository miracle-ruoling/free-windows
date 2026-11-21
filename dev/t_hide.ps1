# Task 4 acceptance: 贴边隐藏 (group glues to the screen edge, slides out, comes back).
#
#   .\t_hide.ps1              # full run on group 1; restores the ini and restarts dock at the end
#
# What it checks, from geometry + the dock's own log:
#   1  switching it on glues the group to the nearest screen edge, kHideGap (15 px) inside
#   2  the pointer leaving the group slides it fully off the screen
#   3  the 唤出区域 band exists at that edge (DockWakeWindow) and matches the group's extent
#   4  moving into the band (wakeMode=enter) brings it back to exactly the same place
#   5  switching it off brings it back and forgets the attachment
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class HD {
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
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
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
[void][HD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { $script:pass++; Write-Output ("  PASS  " + $name + "   " + $detail) }
    else { $script:fail++; Write-Output ("  FAIL  " + $name + "   " + $detail) }
}
function Strip { return [HD]::Find('DockStripWindow') }
function RectOf([IntPtr]$h) { $r = New-Object HD+RECT; [void][HD]::GetWindowRect($h, [ref]$r); return $r }
function RectStr($r) { return "$($r.Left),$($r.Top) $($r.Right - $r.Left)x$($r.Bottom - $r.Top)" }
# the group's bounds = every member united, + the group margin (that is what "15 px inside the
# edge" refers to, not the strip alone - a member can sit a couple of px higher than the strip)
function Bounds {
    $hs = Strip
    $b = RectOf $hs
    $hc = [HD]::Find('DockTrayBarWindow')
    if ($hc -ne [IntPtr]::Zero) {
        $c = RectOf $hc
        if ($c.Left -lt $b.Left) { $b.Left = $c.Left }
        if ($c.Top -lt $b.Top) { $b.Top = $c.Top }
        if ($c.Right -gt $b.Right) { $b.Right = $c.Right }
        if ($c.Bottom -gt $b.Bottom) { $b.Bottom = $c.Bottom }
    }
    $b.Left -= $script:mg; $b.Top -= $script:mg; $b.Right += $script:mg; $b.Bottom += $script:mg
    return $b
}
function BoundsStr($b) { return "$($b.Left),$($b.Top)-$($b.Right),$($b.Bottom)" }
function Reload {
    $h = Strip
    if ($h -ne [IntPtr]::Zero) { [void][HD]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
    Start-Sleep -Milliseconds 900
}
function Restart { Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
                   Start-Process $exe; Start-Sleep -Seconds 2 }
function LogTail([int]$n = 8) { Get-Content $log -Tail 300 | Where-Object { $_ -match 'hide: ' } | Select-Object -Last $n }

$orig = @{
    hideEdge = [HD]::Get('group', 'hideEdge', $null, $ini)
    wakeExt = [HD]::Get('group', 'wakeExt', $null, $ini)
    wakeVisible = [HD]::Get('group', 'wakeVisible', $null, $ini)
    wakeMode = [HD]::Get('group', 'wakeMode', $null, $ini)
    margin = [int][HD]::Get('group', 'margin', '8', $ini)
    stripX = [HD]::Get('dock', 'x', '0', $ini)
    stripY = [HD]::Get('dock', 'y', '0', $ini)
}
$mg = $orig.margin
function Restore {
    foreach ($k in @('hideEdge', 'wakeExt', 'wakeVisible', 'wakeMode')) {
        [void][HD]::Set('group', $k, $orig[$k], $ini)
    }
}
try {
    $h = Strip
    # start from a clean, visible state (a previous run may have left the group hidden)
    [void][HD]::Set('group', 'hideEdge', '0', $ini)
    Restart
    $h = Strip
    $mon = [HD]::Monitor($h)
    [void][HD]::SetCursorPos([int](($mon.Left + $mon.Right) / 2), [int](($mon.Top + $mon.Bottom) / 2))
    Start-Sleep -Milliseconds 400
    $was = RectOf $h
    Write-Output ("strip now " + (RectStr $was) + "   monitor " + $mon.Left + "," + $mon.Top + "-" + $mon.Right + "," + $mon.Bottom)

    Write-Output ""
    Write-Output "== 1. switch it on (nearest edge = top here) =="
    [void][HD]::Set('group', 'hideEdge', '1', $ini)
    [void][HD]::Set('group', 'wakeExt', '6', $ini)
    [void][HD]::Set('group', 'wakeMode', '1', $ini)      # enter to wake
    [void][HD]::Set('group', 'wakeVisible', '0', $ini)
    Restart
    # park the pointer on the group right away: enabling from the panel does not count as
    # "the pointer left", and the arming grace is only 1.5 s
    $g0 = RectOf (Strip)
    [void][HD]::SetCursorPos([int](($g0.Left + $g0.Right) / 2), [int](($g0.Top + $g0.Bottom) / 2))
    Start-Sleep -Milliseconds 600
    $r = RectOf (Strip)
    Write-Output ("  log: " + ((LogTail 3) -join ' | '))
    Write-Output ("  strip " + (RectStr $r) + "   bounds " + (BoundsStr (Bounds)))
    # the glue puts the group's *bounds* 15 px inside the edge
    Check "1  glued to the nearest edge (bounds 15 px inset)" ((Bounds).Top -eq ($mon.Top + 15)) ("bounds.top=" + (Bounds).Top + " expected " + ($mon.Top + 15))
    $awake = $r
    $awakeBounds = Bounds

    Write-Output ""
    Write-Output "== 2. move the pointer away -> it slides out =="
    [void][HD]::SetCursorPos([int](($mon.Left + $mon.Right) / 2), [int](($mon.Top + $mon.Bottom) / 2))
    Start-Sleep -Milliseconds 1200
    $r2 = RectOf (Strip)
    $bo = Bounds
    Write-Output ("  log: " + ((LogTail 2) -join ' | '))
    Write-Output ("  strip " + (RectStr $r2) + "   bounds " + (BoundsStr $bo))
    Check "2  fully off the screen" ($bo.Bottom -le $mon.Top) ("bounds.bottom=" + $bo.Bottom + " monitor.top=" + $mon.Top)
    Check "2  and the bounds sit 5 px past the edge" ($bo.Bottom -eq ($mon.Top - 5)) ("bounds.bottom=" + $bo.Bottom)

    Write-Output ""
    Write-Output "== 3. the 唤出区域 band =="
    $w = [HD]::Find('DockWakeWindow')
    $wr = if ($w -ne [IntPtr]::Zero) { RectOf $w } else { $null }
    Write-Output ("  wake window " + $(if ($w -ne [IntPtr]::Zero) { (RectStr $wr) + " visible=" + [HD]::IsWindowVisible($w) } else { '(none)' }))
    Check "3  band exists at the top edge" ($w -ne [IntPtr]::Zero -and $wr.Top -eq $mon.Top -and $wr.Bottom -eq ($mon.Top + 6)) $(if ($wr) { RectStr $wr } else { '' })
    Check "3  and matches the group's width" ($wr.Left -eq $awakeBounds.Left -and $wr.Right -eq $awakeBounds.Right) ($(if ($wr) { RectStr $wr } else { '' }) + " vs bounds " + $awakeBounds.Left + ".." + $awakeBounds.Right)

    Write-Output ""
    Write-Output "== 4. move into the band -> it comes back =="
    [void][HD]::SetCursorPos([int](($awake.Left + $awake.Right) / 2), $mon.Top + 2)
    Start-Sleep -Milliseconds 1200
    $r3 = RectOf (Strip)
    Write-Output ("  log: " + ((LogTail 2) -join ' | '))
    Write-Output ("  strip now " + (RectStr $r3))
    Check "4  back at the same place" ($r3.Left -eq $awake.Left -and $r3.Top -eq $awake.Top) (RectStr $r3)

    Write-Output ""
    Write-Output "== 5. switch it off =="
    [void][HD]::Set('group', 'hideEdge', '0', $ini)
    Reload
    Start-Sleep -Milliseconds 400
    $r4 = RectOf (Strip)
    $w2 = [HD]::Find('DockWakeWindow')
    Write-Output ("  strip now " + (RectStr $r4) + "   wake visible=" + $(if ($w2 -ne [IntPtr]::Zero) { [HD]::IsWindowVisible($w2) } else { 'n/a' }))
    Check "5  the strip stays where it is once it is off" ($r4.Top -eq $awake.Top) (RectStr $r4)
}
finally {
    Write-Output ""
    Write-Output "== restoring =="
    Restore
    [void][HD]::Set('dock', 'x', $orig.stripX, $ini)
    [void][HD]::Set('dock', 'y', $orig.stripY, $ini)
    Restart
    Start-Sleep -Milliseconds 500
    Write-Output ("  strip after restore " + (RectStr (RectOf (Strip))))
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
