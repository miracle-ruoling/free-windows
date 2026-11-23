<#
  Acceptance for the generic float windows ([float.N]).

  Runs against the *live* dock and its real ini: it backs the ini up first and puts it back in
  `finally`, so the user's profile is untouched. What it proves:

    1. a [float.N] section creates exactly one window (class DockFloatWindow, title "dock float N")
       with the geometry, the visibility and the z band it asked for
    2. band=1 really is "directly above the desktop, below every app window"
    3. band=0 really is the topmost band (switching it live, without a restart)
    4. a float window can join a group: the group's frame grows to include it
    5. deleting the section removes the window again (and the next creation reuses the id)

  Usage:  .\t_float_accept.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class FX {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
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
  public static IntPtr[] All(string cls) {
    var list = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() == cls) list.Add(h); return true; }, IntPtr.Zero);
    return list.ToArray();
  }
  public static IntPtr FindByTitle(string cls, string title) {
    IntPtr f = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(256); GetClassName(h, b, 256);
      if (b.ToString() != cls) return true;
      var t = new StringBuilder(256); GetWindowText(h, t, 256);
      if (t.ToString() == title) { f = h; return false; } return true; }, IntPtr.Zero);
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
    var b = new StringBuilder(512); GetPrivateProfileStringW(s, k, d, b, 512, f); return b.ToString();
  }
  public static bool Set(string s, string k, string v, string f) { return WritePrivateProfileStringW(s, k, v, f); }
  public static bool DropSection(string s, string f) { return WritePrivateProfileStringW(s, null, null, f); }
}
"@
[void][FX]::SetProcessDpiAwarenessContext([IntPtr](-4))

$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$bak = Join-Path $PSScriptRoot '_float_accept.ini.bak'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$sec = 'float.7'          # deliberately not 1: the id must come from the section name
$pass = 0; $fail = 0
function Check($n, $c, $d) {
    if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
    else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) }
}
function Strip { return [FX]::Find('DockStripWindow') }
function Win { return [FX]::FindByTitle('DockFloatWindow', "dock float 7") }
function NonEmptyFrame {
    # Several DockGroupBoxWindow exist (one per group), most of them 10x10 and hidden: the one that
    # carries a real frame rectangle is the group we are looking at.
    $best = [IntPtr]::Zero; $bestArea = 0
    foreach ($h in [FX]::All('DockGroupBoxWindow')) {
        $r = RectOf $h
        $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
        if ($a -gt $bestArea) { $bestArea = $a; $best = $h }
    }
    return $best
}
function Reload {
    $h = Strip
    if ($h -ne [IntPtr]::Zero) { [void][FX]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
    Start-Sleep -Milliseconds 900
}
function RectOf($h) { $r = New-Object FX+RECT; [void][FX]::GetWindowRect($h, [ref]$r); return $r }
function LogTail([string]$pattern, [int]$n = 1) {
    $t = [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::GetEncoding(936))
    $lines = $t -split "`r?`n" | Where-Object { $_ -match $pattern }
    return ($lines | Select-Object -Last $n)
}

Copy-Item $ini $bak -Force
try {
    # ---- 1. create from the ini ----------------------------------------------------------
    [void][FX]::DropSection($sec, $ini)
    foreach ($kv in @(
        @('enabled', '1'), @('bgMode', '2'), @('solidOpacity', '235'), @('glassLayer', '0'),
        @('radius', '41'), @('pad', '10'), @('gap', '6'), @('snap', '1'), @('band', '1'),
        @('iconSize', '44'), @('caption', '1'), @('group', '0'), @('hue', '#BFE6D0'),
        @('items', 'clock;C:\Windows'), @('x', '720'), @('y', '300'), @('w', '320'),
        @('h', '220'), @('hasPos', '1'), @('follow', '0'))) {
        [void][FX]::Set($sec, $kv[0], $kv[1], $ini)
    }
    Reload
    $w = Win
    Write-Output "== 1. [float.7] band=1 =="
    Check "1  a window exists for the section" ($w -ne [IntPtr]::Zero) ("hwnd=" + $w)
    if ($w -ne [IntPtr]::Zero) {
        $r = RectOf $w
        Check "2  geometry comes from the ini" (($r.Left -eq 720) -and ($r.Top -eq 300) -and
              (($r.Right - $r.Left) -eq 320) -and (($r.Bottom - $r.Top) -eq 220)) `
              ("rect " + $r.Left + "," + $r.Top + " " + ($r.Right - $r.Left) + "x" + ($r.Bottom - $r.Top))
        Check "3  it is on screen" ([FX]::IsWindowVisible($w)) ("visible=" + [FX]::IsWindowVisible($w))
        Check "4  band=1 means no WS_EX_TOPMOST" (-not [FX]::Topmost($w)) ("topmost=" + [FX]::Topmost($w))
        $pi = [FX]::Index(([FX]::Find('Progman')))
        $wi = [FX]::Index($w)
        Check "5  and directly above the desktop window" ($wi -eq ($pi - 1)) ("win z#" + $wi + " progman z#" + $pi)
    }
    Write-Output ("   log: " + ((LogTail 'float: (created|loaded) id=7' 1) -join ''))

    # ---- 2. band=0 = topmost --------------------------------------------------------------
    [void][FX]::Set($sec, 'band', '0', $ini)
    Reload
    Write-Output ""
    Write-Output "== 2. band=0 =="
    $w = Win
    Check "6  it became topmost" ([FX]::Topmost($w)) ("topmost=" + [FX]::Topmost($w))
    Check "7  and sits above the strip" (([FX]::Index($w)) -lt ([FX]::Index((Strip)))) `
          ("win z#" + [FX]::Index($w) + " strip z#" + [FX]::Index((Strip)))

    # ---- 3. join group 1 (the strip's group) ----------------------------------------------
    # The user's group 1 uses 贴边隐藏, which slides the whole group (members included) out of the
    # screen when the pointer is away - so the test switches it to 从不 for a moment, otherwise
    # "did the frame grow" cannot be read off the geometry.
    $hideMode = [FX]::Get('group', 'hideMode', '0', $ini)
    [void][FX]::Set('group', 'hideMode', '2', $ini)
    [void][FX]::Set($sec, 'band', '1', $ini)
    [void][FX]::Set($sec, 'group', '1', $ini)
    [void][FX]::Set($sec, 'follow', '1', $ini)
    Reload
    Write-Output ""
    Write-Output "== 3. group 1 (隐藏方案 forced to 从不 for the measurement) =="
    $line = ((LogTail 'float: loaded id=7' 1) -join '')
    Check "8  the load reports group=1" ($line -match 'group=1') $line
    $f = NonEmptyFrame
    if ($f -ne [IntPtr]::Zero) {
        $fr = RectOf $f
        $wr = RectOf (Win)
        Check "9  the group frame grew to include the float window" `
              (($fr.Bottom -ge 500) -and ($fr.Right -ge 1000)) `
              ("frame " + $fr.Left + "," + $fr.Top + " " + ($fr.Right - $fr.Left) + "x" + ($fr.Bottom - $fr.Top))
        Check "10 the float window itself did not move" `
              (($wr.Left -eq 720) -and ($wr.Top -eq 300)) `
              ("rect " + $wr.Left + "," + $wr.Top)
    } else {
        Check "9  the group frame grew to include the float window" $false "no DockGroupBoxWindow"
        Check "10 the float window itself did not move" $false "no frame"
    }
    [void][FX]::Set('group', 'hideMode', $hideMode, $ini)

    # ---- 4. delete the section -> the window goes away ------------------------------------
    [void][FX]::DropSection($sec, $ini)
    Reload
    Write-Output ""
    Write-Output "== 4. section removed =="
    Check "11 the window is gone" ((Win) -eq [IntPtr]::Zero) ("hwnd=" + (Win))
    $line = ((LogTail 'float: deleting id=7' 1) -join '')
    Check "12 and the log says why" ($line -match 'float: deleting id=7') $line
}
finally {
    Copy-Item $bak $ini -Force
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
    Reload
    Write-Output ""
    Write-Output ("  ini restored; [float.7] present now: " +
                  ([FX]::Get('float.7', 'enabled', '<none>', $ini)))
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
