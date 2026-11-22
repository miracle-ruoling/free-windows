# Two remaining checks for the 2026-11-22 evening batch:
#   A  with 璐磋竟闅愯棌 on there is no distance fade at all (the group stays opaque while awake)
#   B  the 鍞ゅ嚭鍖哄煙 uses the group's own 鑹茶皟 ([group] hue), falling back to the strip's tone
#
#   .\t_hidehue.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class HH {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
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
[void][HH]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [HH]::Find('DockStripWindow') }
function Tray { return [HH]::Find('DockTrayBarWindow') }
function RectOf([IntPtr]$h) { $r = New-Object HH+RECT; [void][HH]::GetWindowRect($h, [ref]$r); return $r }
function Restart { Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
                   Start-Process $exe; Start-Sleep -Seconds 2 }
$orig = @{ hideEdge = [HH]::Get('group', 'hideEdge', $null, $ini)
           wakeVisible = [HH]::Get('group', 'wakeVisible', $null, $ini)
           wakeExt = [HH]::Get('group', 'wakeExt', $null, $ini)
           hue = [HH]::Get('group', 'hue', $null, $ini) }
function Restore { foreach ($k in 'hideEdge', 'wakeVisible', 'wakeExt', 'hue') { [void][HH]::Set('group', $k, $orig.$k, $ini) } }
try {
    # ---- A: no distance fade while 璐磋竟闅愯棌 is on -----------------------------------------
    [void][HH]::Set('group', 'hideEdge', '1', $ini)
    [void][HH]::Set('group', 'wakeVisible', '1', $ini)
    [void][HH]::Set('group', 'wakeExt', '8', $ini)
    Restart
    $s = RectOf (Strip); $c = RectOf (Tray)
    $bb = [math]::Max($s.Bottom, $c.Bottom) + 13
    $x = [int](($s.Left + $s.Right) / 2)
    $mark = (Get-Content $log).Count
    [void][HH]::SetCursorPos($x, [int](($s.Top + $s.Bottom) / 2)); Start-Sleep -Milliseconds 500
    # 10 px outside the bounds: inside the +20 px pad, so the group stays awake
    [void][HH]::SetCursorPos($x, $bb + 10); Start-Sleep -Milliseconds 900
    $fadeLines = @(Get-Content $log | Select-Object -Skip $mark | Where-Object { $_ -match 'fade: ' })
    Write-Output ("== A. 璐磋竟闅愯棌 on, pointer 10 px outside ==")
    Write-Output ("  fade lines after the move: " + $fadeLines.Count)
    Check "A  no distance fade any more" ($fadeLines.Count -eq 0) ("fade lines: " + $fadeLines.Count)

    # ---- B: the band uses [group] hue -------------------------------------------------
    # The band is painted at 甯告樉 alpha (~16 %), which is subtle on that wallpaper, so compare the
    # band's row with the row just below it (same wallpaper) and do it for two hues: the colour
    # that wins has to follow the group's 鑹茶皟.
    function BandDelta([int]$midX, [int]$top, [int]$bottom, [int]$w) {
        $bmp = New-Object System.Drawing.Bitmap 1920, 1080
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1920, 1080))
        $g.Dispose()
        $aR = 0.0; $aG = 0.0; $aB = 0.0; $bR = 0.0; $bG = 0.0; $bB = 0.0; $n = 0
        for ($x = $midX - 40; $x -le $midX + 40; $x += 4) {
            $p1 = $bmp.GetPixel($x, [int](($top + $bottom) / 2))
            $p2 = $bmp.GetPixel($x, $bottom + 6)
            $aR += $p1.R; $aG += $p1.G; $aB += $p1.B
            $bR += $p2.R; $bG += $p2.G; $bB += $p2.B
            $n++
        }
        $bmp.Dispose()
        return @{ dR = ($aR - $bR) / $n; dG = ($aG - $bG) / $n; dB = ($aB - $bB) / $n }
    }
    function SetHueAndHide([string]$hex) {
        [void][HH]::Set('group', 'hue', $hex, $ini)
        $h = Strip; [void][HH]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 800
        [void][HH]::SetCursorPos(400, 900); Start-Sleep -Milliseconds 1500     # hide it
        $w = [HH]::Find('DockWakeWindow')
        if ($w -eq [IntPtr]::Zero) { throw 'no wake window' }
        return (RectOf $w)
    }
    $wr = SetHueAndHide '#00FF00'
    $grn = BandDelta ([int](($wr.Left + $wr.Right) / 2)) $wr.Top $wr.Bottom ($wr.Right - $wr.Left)
    $wr2 = SetHueAndHide '#0000FF'
    $blue = BandDelta ([int](($wr2.Left + $wr2.Right) / 2)) $wr2.Top $wr2.Bottom ($wr2.Right - $wr2.Left)
    Write-Output ""
    Write-Output ("== B. band colour follows [group] hue ==")
    Write-Output ("  band " + $wr.Left + "," + $wr.Top + " " + ($wr.Right - $wr.Left) + "x" + ($wr.Bottom - $wr.Top))
    Write-Output ("  hue #00FF00 -> dR=" + [math]::Round($grn.dR, 1) + " dG=" + [math]::Round($grn.dG, 1) + " dB=" + [math]::Round($grn.dB, 1))
    Write-Output ("  hue #0000FF -> dR=" + [math]::Round($blue.dR, 1) + " dG=" + [math]::Round($blue.dG, 1) + " dB=" + [math]::Round($blue.dB, 1))
    # the two hues have to push the band in different directions: that is what proves the band
    # reads the group's 色调 rather than a fixed colour
    Check "B  green hue tints the band green" ($grn.dG -gt $blue.dG + 8 -and $grn.dG -gt 2) ("dG " + [math]::Round($grn.dG, 1) + " vs blue " + [math]::Round($blue.dG, 1))
    Check "B  blue hue tints it blue instead" ($blue.dB -gt $blue.dG + 8 -and $blue.dB -gt 2) ("dB " + [math]::Round($blue.dB, 1))
}
finally {
    Restore
    Restart
    Write-Output ""
    Write-Output ("  restored hideEdge='" + [HH]::Get('group', 'hideEdge', '', $ini) + "' hue='" + [HH]::Get('group', 'hue', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }


