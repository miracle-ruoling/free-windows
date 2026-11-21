# Task 2 acceptance: [dock] dodgeOnDoubleClick must add/remove *only* the dodge gesture.
#
#   .\t_dodge.ps1              # full run: off -> nothing moves; on -> moves; then back on
#   .\t_dodge.ps1 -Keep 0      # leave the key at 0 (the default run restores 1)
#
# The ini is written with WritePrivateProfileStringW (real ANSI/GBK profile write), never
# with PowerShell text I/O: the deployed dock.ini has Chinese picture paths and a UTF-8
# round trip destroys them (HANDOVER_NEXT.md §3.28).
param([ValidateSet("0", "1")][string]$Keep = "1")
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class DG {
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetPrivateProfileStringW(string sec, string key, string def, StringBuilder sb, int n, string file);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool WritePrivateProfileStringW(string sec, string key, string val, string file);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  public static string Get(string sec, string key, string def, string file) {
    var sb = new StringBuilder(64);
    GetPrivateProfileStringW(sec, key, def, sb, 64, file);
    return sb.ToString();
  }
}
"@
[void][DG]::SetProcessDpiAwarenessContext([IntPtr](-4))

$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$h = [DG]::Find('DockStripWindow')
if ($h -eq [IntPtr]::Zero) { throw "DockStripWindow not found - is dock running?" }
$pass = 0; $fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { $script:pass++; Write-Output ("  PASS  " + $name + "   " + $detail) }
    else { $script:fail++; Write-Output ("  FAIL  " + $name + "   " + $detail) }
}

function Set-Key([string]$v) {
    [void][DG]::WritePrivateProfileStringW('dock', 'dodgeOnDoubleClick', $v, $ini)
    [void][DG]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]0)   # WM_TIMER 2 -> Reload() (t_dock_reload)
    Start-Sleep -Milliseconds 700
    return [DG]::Get('dock', 'dodgeOnDoubleClick', '?', $ini)
}

# one double click on the strip's left padding (empty strip: left of the first icon)
function Double-ClickBlank {
    $r = New-Object DG+RECT
    [void][DG]::GetWindowRect($h, [ref]$r)
    $cx = 40
    $cy = [int](($r.Bottom - $r.Top) / 2)
    $lp = [IntPtr](($cy -shl 16) -bor ($cx -band 0xFFFF))
    for ($i = 0; $i -lt 4; $i++) {
        [void][DG]::PostMessage($h, 0x0201, [IntPtr]1, $lp)
        Start-Sleep -Milliseconds 25
        [void][DG]::PostMessage($h, 0x0202, [IntPtr]0, $lp)
        Start-Sleep -Milliseconds 120
        [void][DG]::PostMessage($h, 0x0201, [IntPtr]1, $lp)
        Start-Sleep -Milliseconds 25
        [void][DG]::PostMessage($h, 0x0202, [IntPtr]0, $lp)
        Start-Sleep -Milliseconds 500
        if (Get-Content $log -Tail 60 | Where-Object { $_ -match 'flip: ' } | Select-Object -Last 1) {
            # a flip line exists; whether it is a *new* one is judged by the caller
            return
        }
    }
}

function Strip-Pos {
    $r = New-Object DG+RECT
    [void][DG]::GetWindowRect($h, [ref]$r)
    return "$($r.Left),$($r.Top)"
}
function Log-Lines([int]$n = 6) {
    return @(Get-Content $log -Tail 80 | Where-Object { $_ -match 'flip: ' } | Select-Object -Last $n)
}
function Mirror-Y {
    $r = New-Object DG+RECT
    [void][DG]::GetWindowRect($h, [ref]$r)
    $mi = New-Object DG+MONITORINFO
    $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
    [void][DG]::GetMonitorInfo([DG]::MonitorFromWindow($h, 2), [ref]$mi)
    $wa = $mi.rcWork
    return $wa.Top + $wa.Bottom - $r.Top - ($r.Bottom - $r.Top)
}

$orig = Strip-Pos
$before = (Log-Lines 1)
Write-Output ("strip now at " + $orig + "   dodgeOnDoubleClick=" + [DG]::Get('dock', 'dodgeOnDoubleClick', '(absent)', $ini))

# ---- OFF: nothing may move, and no flip may start ------------------------------------------
Write-Output ""
Write-Output "== dodgeOnDoubleClick=0 =="
Write-Output ("  ini now: " + (Set-Key '0'))
$p0 = Strip-Pos
Double-ClickBlank
Start-Sleep -Milliseconds 600
$p1 = Strip-Pos
$lines1 = Log-Lines 3
Write-Output ("  strip " + $p0 + " -> " + $p1)
Write-Output ("  last flip lines: " + (($lines1 | ForEach-Object { $_.Trim() }) -join " / "))
Check "OFF  the strip did not move" ($p0 -eq $p1) "$p0 -> $p1"
Check "OFF  no new flip was started" (($lines1.Count -eq $before.Count) -or ($lines1[0] -eq $before[0])) "log unchanged"

# ---- ON: the dodge must work exactly as before --------------------------------------------
Write-Output ""
Write-Output "== dodgeOnDoubleClick=1 =="
Write-Output ("  ini now: " + (Set-Key '1'))
$expect = Mirror-Y
$q0 = Strip-Pos
Double-ClickBlank
Start-Sleep -Milliseconds 800
$q1 = Strip-Pos
Write-Output ("  strip " + $q0 + " -> " + $q1 + "   (mirror would be y=" + $expect + ")")
Check "ON   the strip dodged" ($q0 -ne $q1) "$q0 -> $q1"
Check "ON   it landed on the mirrored side" ($q1 -match (",$expect$")) "$q1"

# ---- put it back: a second double click mirrors it home, key back to the requested value ----
Double-ClickBlank
Start-Sleep -Milliseconds 800
$back = Strip-Pos
Write-Output ""
Write-Output ("after dodging back: " + $back + "   (was " + $orig + ")")
if ($back -ne $orig) {
    Write-Output "  !! the strip is not where it started - restore it by hand in the settings"
}
Write-Output ("ini left at dodgeOnDoubleClick=" + (Set-Key $Keep))

Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
