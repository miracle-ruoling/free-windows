# Task 3 acceptance: the snap (贴边方角) is now a per-window switch.
#
#   .\t_snap.ps1              # full run; restores every ini value and restarts dock at the end
#   .\t_snap.ps1 -NoStrip     # companion half only (no dock restart for the strip case)
#
# What it proves, from the dock's own log ("snap: ... corners TL=.. TR=.. BL=.. BR=.."), which is
# written every time a corner target actually changes:
#   A  the companion (which never had the behaviour) now snaps when it hugs an edge
#   B  [traybar] snap=0 turns it off for that window only
#   C  inheriting: [traybar] snap absent + [dock] snap=0 -> off through the strip's key
#   D  back to inheriting with [dock] snap=1 -> on again
#   E  the strip still snaps when it hugs an edge ([dock] y=0)
#   F  [dock] snap=0 turns the strip's own snap off
#   G  and back on
# Everything goes through WritePrivateProfileStringW (ANSI/GBK profile write). NEVER rewrite
# dock.ini with PowerShell text I/O: the picture paths are GBK and a UTF-8 round trip kills them.
param([switch]$NoStrip)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class SP {
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
    var sb = new StringBuilder(128);
    GetPrivateProfileStringW(sec, key, def, sb, 128, file);
    return sb.ToString();
  }
  public static bool Set(string sec, string key, string val, string file) {
    // a null value deletes the key - that is how "inherit" is expressed
    return WritePrivateProfileStringW(sec, key, val, file);
  }
  public static RECT Work(IntPtr h) {
    var mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(mi);
    GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
    return mi.rcWork;
  }
}
"@
[void][SP]::SetProcessDpiAwarenessContext([IntPtr](-4))

$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { $script:pass++; Write-Output ("  PASS  " + $name + "   " + $detail) }
    else { $script:fail++; Write-Output ("  FAIL  " + $name + "   " + $detail) }
}
function Strip { return [SP]::Find('DockStripWindow') }
function Reload {
    $h = Strip
    if ($h -ne [IntPtr]::Zero) { [void][SP]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
    Start-Sleep -Milliseconds 900
}
function RestartDock {
    Stop-Process -Name dock -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Start-Process $exe
    Start-Sleep -Seconds 2
}
# the last "snap:" line, as "TL TR BL BR" digits, newest only
function LastSnapCorners([string]$which) {
    $pat = if ($which -eq 'tray') { 'snap: traybar corners TL=(\d) TR=(\d) BL=(\d) BR=(\d)' }
                                 else { 'snap: corners TL=(\d) TR=(\d) BL=(\d) BR=(\d)' }
    $line = Get-Content $log -Tail 400 | Where-Object { $_ -match $pat } | Select-Object -Last 1
    if (-not $line) { return '' }
    $line -match $pat | Out-Null
    return "$($Matches[1])$($Matches[2])$($Matches[3])$($Matches[4])"
}
function LastSnapLine([string]$which) {
    $pat = if ($which -eq 'tray') { 'snap: traybar corners' } else { 'snap: corners' }
    $l = Get-Content $log -Tail 400 | Where-Object { $_ -match $pat } | Select-Object -Last 1
    if ($l) { return $l.Trim() } else { return '(none)' }
}

# ---- keep everything we are about to touch -------------------------------------------------
$hStrip = Strip
$hTray = [SP]::Find('DockTrayBarWindow')
if ($hStrip -eq [IntPtr]::Zero) { throw "dock is not running" }
$orig = @{
    dock_x = [SP]::Get('dock', 'x', '0', $ini)
    dock_y = [SP]::Get('dock', 'y', '0', $ini)
    dock_hasPos = [SP]::Get('dock', 'hasPos', '0', $ini)
    dock_snap = [SP]::Get('dock', 'snap', $null, $ini)
    tray_x = [SP]::Get('traybar', 'x', '0', $ini)
    tray_y = [SP]::Get('traybar', 'y', '0', $ini)
    tray_w = [SP]::Get('traybar', 'w', '319', $ini)
    tray_h = [SP]::Get('traybar', 'h', '93', $ini)
    tray_snap = [SP]::Get('traybar', 'snap', $null, $ini)
}
function Restore {
    [void][SP]::Set('dock', 'x', $orig.dock_x, $ini)
    [void][SP]::Set('dock', 'y', $orig.dock_y, $ini)
    [void][SP]::Set('dock', 'hasPos', $orig.dock_hasPos, $ini)
    [void][SP]::Set('dock', 'snap', $orig.dock_snap, $ini)
    [void][SP]::Set('traybar', 'x', $orig.tray_x, $ini)
    [void][SP]::Set('traybar', 'y', $orig.tray_y, $ini)
    [void][SP]::Set('traybar', 'snap', $orig.tray_snap, $ini)
}
$wa = [SP]::Work($hTray)
$th = [int]$orig.tray_h
$flushY = $wa.Bottom - $th
Write-Output ("work area " + $wa.Left + "," + $wa.Top + "-" + $wa.Right + "," + $wa.Bottom +
              "   companion " + $orig.tray_w + "x" + $th + " -> flush y=" + $flushY)
Write-Output ("ini before: dock snap='" + $orig.dock_snap + "' tray snap='" + $orig.tray_snap + "'")

try {
    # ---- A: the companion hugs the bottom edge -------------------------------------------
    Write-Output ""
    Write-Output "== A. companion flush to the bottom edge, snap inherited (on) =="
    [void][SP]::Set('dock', 'snap', '1', $ini)
    [void][SP]::Set('traybar', 'snap', $null, $ini)
    [void][SP]::Set('traybar', 'y', "$flushY", $ini)
    RestartDock
    $c = LastSnapCorners 'tray'
    Write-Output ("  log: " + (LastSnapLine 'tray'))
    Check "A  companion squares its bottom corners" ($c -eq '1100') "corners=$c (TL TR BL BR)"

    # ---- B: its own switch ---------------------------------------------------------------
    Write-Output ""
    Write-Output "== B. [traybar] snap=0 =="
    [void][SP]::Set('traybar', 'snap', '0', $ini)
    Reload
    $c = LastSnapCorners 'tray'
    Write-Output ("  log: " + (LastSnapLine 'tray'))
    Check "B  its own switch turns the snap off" ($c -eq '1111') "corners=$c"
    Check "B  and the window stayed at the edge" ([SP]::Get('traybar', 'y', '?', $ini) -eq "$flushY") "y=$flushY"

    # ---- B2: back to inherit (real transition, so the next case cannot pass on a stale line)
    Write-Output ""
    Write-Output "== B2. [traybar] snap back to inherit =="
    [void][SP]::Set('traybar', 'snap', $null, $ini)
    Reload
    $c = LastSnapCorners 'tray'
    Write-Output ("  log: " + (LastSnapLine 'tray'))
    Check "B2 inheriting snaps again" ($c -eq '1100') "corners=$c"

    # ---- C: inheriting from the strip ----------------------------------------------------
    Write-Output ""
    Write-Output "== C. tray snap=inherit, [dock] snap=0 =="
    [void][SP]::Set('dock', 'snap', '0', $ini)
    Reload
    $c = LastSnapCorners 'tray'
    Write-Output ("  log: " + (LastSnapLine 'tray'))
    Check "C  the strip's switch reaches the companion through inherit" ($c -eq '1111') "corners=$c"

    # ---- D: back to inheriting, strip on -------------------------------------------------
    Write-Output ""
    Write-Output "== D. [dock] snap=1 again =="
    [void][SP]::Set('dock', 'snap', '1', $ini)
    Reload
    $c = LastSnapCorners 'tray'
    Write-Output ("  log: " + (LastSnapLine 'tray'))
    Check "D  snapping comes back" ($c -eq '1100') "corners=$c"

    if (-not $NoStrip) {
        # ---- E/F/G: the strip's own switch (needs it flush to an edge) --------------------
        Write-Output ""
        Write-Output "== E. strip flush to the top edge (dock y=0), snap on =="
        [void][SP]::Set('traybar', 'y', $orig.tray_y, $ini)      # put the companion back first
        [void][SP]::Set('dock', 'y', '0', $ini)
        [void][SP]::Set('dock', 'hasPos', '1', $ini)
        RestartDock
        $c = LastSnapCorners 'strip'
        Write-Output ("  log: " + (LastSnapLine 'strip'))
        Check "E  strip squares its top corners" ($c -eq '0011') "corners=$c (TL TR BL BR)"

        Write-Output ""
        Write-Output "== F. [dock] snap=0 =="
        [void][SP]::Set('dock', 'snap', '0', $ini)
        Reload
        $c = LastSnapCorners 'strip'
        Write-Output ("  log: " + (LastSnapLine 'strip'))
        Check "F  the strip's switch turns its snap off" ($c -eq '1111') "corners=$c"

        Write-Output ""
        Write-Output "== G. [dock] snap=1 =="
        [void][SP]::Set('dock', 'snap', '1', $ini)
        Reload
        $c = LastSnapCorners 'strip'
        Write-Output ("  log: " + (LastSnapLine 'strip'))
        Check "G  and back on" ($c -eq '0011') "corners=$c"
    }
}
finally {
    Write-Output ""
    Write-Output "== restoring the ini and restarting dock =="
    Restore
    RestartDock
    Write-Output ("  dock snap='" + [SP]::Get('dock', 'snap', $null, $ini) + "' tray snap='" +
                  [SP]::Get('traybar', 'snap', $null, $ini) + "' dock y=" +
                  [SP]::Get('dock', 'y', '?', $ini) + " tray y=" + [SP]::Get('traybar', 'y', '?', $ini))
}

Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
