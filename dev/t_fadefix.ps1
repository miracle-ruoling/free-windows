# Fade fixes (2026-11-22 evening):
#   A  with 璐磋竟闅愯棌 off, the strip and the companion must show the SAME alpha at the same distance
#      (one fade per group, measured to the group's bounds with the group's numbers)
#   B  with 璐磋竟闅愯棌 on there is no distance fade at all: the group stays fully opaque while awake
#
#   .\t_fadefix.ps1
# Alpha is estimated from pixels: the layered windows composite over the desktop, so with the same
# content at three pointer distances
#     a = (p_at_d - p_desktop) / (p_opaque - p_desktop)
# gives the window's alpha at distance d. p_desktop = the pixel while the group is fully faded.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class FD {
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
[void][FD]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function Strip { return [FD]::Find('DockStripWindow') }
function Tray { return [FD]::Find('DockTrayBarWindow') }
function RectOf([IntPtr]$h) { $r = New-Object FD+RECT; [void][FD]::GetWindowRect($h, [ref]$r); return $r }
function Restart { Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
                   Start-Process $exe; Start-Sleep -Seconds 2 }
function Reload { $h = Strip; if ($h -ne [IntPtr]::Zero) { [void][FD]::PostMessage($h, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
                  Start-Sleep -Milliseconds 900 }

# grab one full-screen frame and return it (a Bitmap)
function Shot {
    $bmp = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1920, 1080))
    $g.Dispose()
    return $bmp
}
function Sample($bmp, $p) { $c = $bmp.GetPixel($p.x, $p.y); return @($c.R, $c.G, $c.B) }
# Mean colour over a grid inside a rect: one pixel can be a coincidence (a picture background that
# happens to look like the wallpaper), the mean of 15 points is not.
function MeanRect($bmp, $r) {
    $sr = 0.0; $sg = 0.0; $sb = 0.0; $n = 0
    for ($fx = 1; $fx -le 5; $fx++) {
        for ($fy = 1; $fy -le 3; $fy++) {
            $x = $r.Left + [int](($r.Right - $r.Left) * $fx / 6)
            $y = $r.Top + [int](($r.Bottom - $r.Top) * $fy / 4)
            $c = $bmp.GetPixel($x, $y)
            $sr += $c.R; $sg += $c.G; $sb += $c.B; $n++
        }
    }
    return @(($sr / $n), ($sg / $n), ($sb / $n))
}

$orig = @{ hideEdge = [FD]::Get('group', 'hideEdge', $null, $ini)
           wakeVisible = [FD]::Get('group', 'wakeVisible', $null, $ini) }
function Restore { [void][FD]::Set('group', 'hideEdge', $orig.hideEdge, $ini)
                   [void][FD]::Set('group', 'wakeVisible', $orig.wakeVisible, $ini) }

try {
    # ---- baseline geometry ----
    [void][FD]::Set('group', 'hideEdge', '0', $ini)
    Restart
    $s = RectOf (Strip); $c = RectOf (Tray)
    $sx = [int](($s.Left + $s.Right) / 2); $sy = [int](($s.Top + $s.Bottom) / 2)
    $cx = [int](($c.Left + $c.Right) / 2); $cy = [int](($c.Top + $c.Bottom) / 2)
    $pStrip = @{ x = $sx; y = $sy }
    $pComp = @{ x = $cx; y = $cy }
    Write-Output ("strip " + $s.Left + "," + $s.Top + "  tray " + $c.Left + "," + $c.Top)

    # ---- the three reference frames for the strip's own group ----
    # opaque: pointer inside the strip; faded: pointer far away (alpha 0)
    [void][FD]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 500
    $on = Shot
    [void][FD]::SetCursorPos(200, 900); Start-Sleep -Milliseconds 600
    $off = Shot
    # 18 px below the group's bounds: distance 18 with fadeStart=0/fadeEnd=80 -> about 55 % alpha
    $midY = ($c.Bottom + 13) + 18
    [void][FD]::SetCursorPos($cx, $midY); Start-Sleep -Milliseconds 600
    $mid = Shot

    function AlphaFrom($onB, $offB, $midB, $r) {   # 1 - |mid-on| / |off-on| over a grid
        $dm = 0.0; $do = 0.0; $n = 0
        for ($fx = 1; $fx -le 6; $fx++) {
            for ($fy = 1; $fy -le 4; $fy++) {
                $x = $r.Left + [int](($r.Right - $r.Left) * $fx / 7)
                $y = $r.Top + [int](($r.Bottom - $r.Top) * $fy / 5)
                $a1 = $onB.GetPixel($x, $y); $a2 = $offB.GetPixel($x, $y); $a3 = $midB.GetPixel($x, $y)
                $dm += [math]::Abs($a3.R - $a1.R) + [math]::Abs($a3.G - $a1.G) + [math]::Abs($a3.B - $a1.B)
                $do += [math]::Abs($a2.R - $a1.R) + [math]::Abs($a2.G - $a1.G) + [math]::Abs($a2.B - $a1.B)
                $n++
            }
        }
        if ($do -lt ($n * 6)) { return -1 }        # the window does not change at all: no signal
        return 100.0 * (1.0 - $dm / $do)
    }
    $aStripOff = AlphaFrom $on $off $mid $s
    $aCompOff = AlphaFrom $on $off $mid $c
    Write-Output ""
    Write-Output ("== A. 璐磋竟闅愯棌 off, pointer 18 px outside the group ==")
    Write-Output ("  strip alpha ~" + [math]::Round($aStripOff, 0) + " %   companion alpha ~" + [math]::Round($aCompOff, 0) + " %")
    Check "A  both windows fade to the same value" ($aStripOff -ge 0 -and $aCompOff -ge 0 -and [math]::Abs($aStripOff - $aCompOff) -le 6) ("delta " + [math]::Round([math]::Abs($aStripOff - $aCompOff), 0) + " %")
    Check "A  and they really are mid-fade (not 0, not 100)" ($aStripOff -gt 15 -and $aStripOff -lt 90) ([math]::Round($aStripOff, 0))

    # ---- B: with 璐磋竟闅愯棌 on the same gesture keeps them fully opaque ----
    [void][FD]::Set('group', 'hideEdge', '1', $ini)
    [void][FD]::Set('group', 'wakeVisible', '0', $ini)
    Restart
    $s = RectOf (Strip); $c = RectOf (Tray)
    $sx = [int](($s.Left + $s.Right) / 2); $sy = [int](($s.Top + $s.Bottom) / 2)
    $cx = [int](($c.Left + $c.Right) / 2)
    [void][FD]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 600      # awake, arm the grace
    $on2 = Shot
    $midY2 = ($c.Bottom + 13) + 18
    [void][FD]::SetCursorPos($cx, $midY2); Start-Sleep -Milliseconds 450    # inside the +20 pad
    $mid2 = Shot
    $bStrip = AlphaFrom $on2 $off $mid2 $s
    $bComp = AlphaFrom $on2 $off $mid2 $c
    Write-Output ""
    Write-Output ("== B. 璐磋竟闅愯棌 on, same 18 px ==")
    Write-Output ("  strip alpha ~" + [math]::Round($bStrip, 0) + " %   companion alpha ~" + [math]::Round($bComp, 0) + " %")
    Check "B  no distance fade any more (both opaque)" ($bStrip -ge 96 -and $bComp -ge 96) ("strip " + [math]::Round($bStrip, 0) + "%, tray " + [math]::Round($bComp, 0) + "%")

    $on.Dispose(); $off.Dispose(); $mid.Dispose(); $on2.Dispose(); $mid2.Dispose()
}
finally {
    Restore
    Restart
    Write-Output ""
    Write-Output "  restored (hideEdge='" + [FD]::Get('group', 'hideEdge', '', $ini) + "')"
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }



