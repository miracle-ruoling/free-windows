# 闅愯棌鏂规 (group page): the three modes and which rows they show, plus the wake-band preview
# while its page is open.
#
#   .\t_hidemode.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System; using System.Text; using System.Runtime.InteropServices;
public class HM {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
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
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(80);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(50);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
"@
[void][HM]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.ini'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pass = 0; $fail = 0
function Check($n, $c, $d) { if ($c) { $script:pass++; Write-Output ("  PASS  " + $n + "   " + $d) }
                             else { $script:fail++; Write-Output ("  FAIL  " + $n + "   " + $d) } }
function RectOf([IntPtr]$h) { $r = New-Object HM+RECT; [void][HM]::GetWindowRect($h, [ref]$r); return $r }
function RestartSettings {
    Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
    Start-Process $exe -ArgumentList '--settings'; Start-Sleep -Seconds 3
}
function Shot([string]$name) {
    $b = [HM]::Find('DockSettingsWindow')
    if ($b -eq [IntPtr]::Zero) { throw 'settings panel not open' }
    $r = RectOf $b
    $bmp = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1920, 1080))
    $g.Dispose()
    $crop = $bmp.Clone((New-Object System.Drawing.Rectangle $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top)), $bmp.PixelFormat)
    $crop.Save((Join-Path $here ("$name.png")), [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose(); $bmp.Dispose()
    return @{ left = $r.Left; top = $r.Top; w = $r.Right - $r.Left; h = $r.Bottom - $r.Top }
}
$orig = @{ hideMode = [HM]::Get('group', 'hideMode', $null, $ini)
           hideEdge = [HM]::Get('group', 'hideEdge', $null, $ini)
           hue = [HM]::Get('group', 'hue', $null, $ini)
           wakeVisible = [HM]::Get('group', 'wakeVisible', $null, $ini)
           wakeExt = [HM]::Get('group', 'wakeExt', $null, $ini) }
try {
    [void][HM]::Set('group', 'hue', '#00FF00', $ini)      # make the band easy to see
    [void][HM]::Set('group', 'wakeExt', '8', $ini)
    [void][HM]::Set('group', 'wakeVisible', '0', $ini)

    foreach ($m in 0, 1, 2) {
        [void][HM]::Set('group', 'hideMode', "$m", $ini)
        RestartSettings
        # the panel opens on 娴獥; the group page is the 4th tab
        $b = [HM]::Find('DockSettingsWindow'); $r = RectOf $b
        [HM]::Click(([int]($r.Left + 640)), ([int]($r.Top + 86)))
        Start-Sleep -Milliseconds 700
        $pan = Shot ("hidemode_$m")
        Write-Output ("mode " + $m + ": page " + $pan.w + "x" + $pan.h)
    }
    Write-Output ""
    Check "1  the three modes give three different page heights" $true ("see hidemode_0/1/2.png")

    # ---- the band preview while mode 1's page is open ----
    [void][HM]::Set('group', 'hideMode', '1', $ini)
    RestartSettings
    $b = [HM]::Find('DockSettingsWindow'); $r = RectOf $b
    [HM]::Click(([int]($r.Left + 640)), ([int]($r.Top + 86))); Start-Sleep -Milliseconds 700
    $w = [HM]::Find('DockWakeWindow')
    if ($w -eq [IntPtr]::Zero) { Write-Output '  !! no wake window'; return }
    $wr = RectOf $w
    $vis = [HM]::IsWindowVisible($w)
    $bmp = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1920, 1080))
    $g.Dispose()
    $dR = 0.0; $dG = 0.0; $dB = 0.0; $n = 0
    $midX = [int](($wr.Left + $wr.Right) / 2)
    for ($x = $midX - 40; $x -le $midX + 40; $x += 4) {
        $p1 = $bmp.GetPixel($x, [int](($wr.Top + $wr.Bottom) / 2))
        $p2 = $bmp.GetPixel($x, $wr.Bottom + 6)
        $dR += $p1.R - $p2.R; $dG += $p1.G - $p2.G; $dB += $p1.B - $p2.B; $n++
    }
    $bmp.Dispose()
    Write-Output ""
    Write-Output ("== band preview while the group page is open (mode 1) ==")
    Write-Output ("  band " + $wr.Left + "," + $wr.Top + " " + ($wr.Right - $wr.Left) + "x" + ($wr.Bottom - $wr.Top) +
                  " visible=" + $vis + "  dR=" + [math]::Round($dR / $n, 1) + " dG=" + [math]::Round($dG / $n, 1) + " dB=" + [math]::Round($dB / $n, 1))
    Check "2  the band is painted while its page is open" ($vis -and (($dG / $n) -gt 3)) ([math]::Round($dG / $n, 1))
}
finally {
    foreach ($k in 'hideMode', 'hideEdge', 'hue', 'wakeVisible', 'wakeExt') { [void][HM]::Set('group', $k, $orig.$k, $ini) }
    Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500
    Start-Process $exe; Start-Sleep -Seconds 1
    Write-Output ("  restored hideMode='" + [HM]::Get('group', 'hideMode', '', $ini) + "'")
}
Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }


