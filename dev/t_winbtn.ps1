# Click the fixed Windows button on the strip and report what the shell did.
#   -Button left  -> Start menu via Ctrl+Esc  (the taskbar mod must not react)
#   -Button right -> Win+X menu               (the dock hides the taskbar again)
param([ValidateSet("left","right")][string]$Button = "left", [switch]$NoClick)
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WC {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R;
    public string Show() { return string.Format("{0} cls={1} txt='{2}' pid={3} vis={4} rect={5},{6} {7}x{8}",
        H, Cls, Txt, Pid, Vis, R.Left, R.Top, R.Right-R.Left, R.Bottom-R.Top); }
  }
  public static List<Info> All() {
    List<Info> l = new List<Info>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      Info i = new Info(); i.H = h;
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200); i.Cls = b.ToString();
      StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200); i.Txt = t.ToString();
      uint p; GetWindowThreadProcessId(h, out p); i.Pid = p;
      i.Vis = IsWindowVisible(h);
      RECT r; GetWindowRect(h, out r); i.R = r;
      l.Add(i);
      return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WC]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WC]::GetSystemMetrics(0)), ([WC]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WC]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WC]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
function State([string]$tag) {
    Write-Output ("--- " + $tag + " ---")
    foreach ($w in ([WC]::All())) {
        if ($w.Cls -eq "Shell_TrayWnd" -or $w.Cls -eq "Shell_SecondaryTrayWnd") {
            Write-Output ("  bar  " + $w.Show() + " vis=" + $w.Vis)
        }
        if ($w.Cls -like "Xaml_WindowedPopupClass*" -and $w.Vis) {
            Write-Output ("  popup " + $w.Show())
        }
    }
    foreach ($h in $script:barHandles) {
        $rr = New-Object WC+RECT
        $ok = [WC]::GetWindowRect($h, [ref]$rr)
        Write-Output ("  remembered bar " + $h.ToInt64() + " rect=" + $rr.Left + "," + $rr.Top + " " + ($rr.Right-$rr.Left) + "x" + ($rr.Bottom-$rr.Top) + " ok=" + $ok)
    }
}
# strip rect + the win cell from the layout log (win=23,24-95,96 in client coords)
$strip = [IntPtr]::Zero
foreach ($w in ([WC]::All())) { if ($w.Cls -eq "DockStripWindow") { $strip = $w.H; break } }
$r = New-Object WC+RECT
if ($strip -eq [IntPtr]::Zero -or -not [WC]::GetWindowRect($strip, [ref]$r)) {
    Write-Output "strip not found (FindWindow=$strip)"; exit 1
}
Write-Output ("strip=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
$log = Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 400 |
       Select-String -Pattern "layout: " | Select-Object -Last 1
if (-not $log) { Write-Output "no layout line in the log"; exit 1 }
if ($log.Line -notmatch "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { Write-Output ("cannot parse: " + $log.Line); exit 1 }
$wl = [int]$Matches[1]; $wt = [int]$Matches[2]; $wr2 = [int]$Matches[3]; $wb = [int]$Matches[4]
$cx = $r.Left + [int](($wl + $wr2) / 2)
$cy = $r.Top + [int](($wt + $wb) / 2)
Write-Output ("win cell client=" + $wl + "," + $wt + "-" + $wr2 + "," + $wb + " -> screen " + $cx + "," + $cy)
$script:barHandles = @()
foreach ($w in ([WC]::All())) {
    if ($w.Cls -eq "Shell_TrayWnd" -or $w.Cls -eq "Shell_SecondaryTrayWnd") { $script:barHandles += $w.H }
}
Write-Output ("remembered taskbar handles: " + (($script:barHandles | ForEach-Object { $_.ToInt64() }) -join ','))
State "before"
Esc; Start-Sleep -Milliseconds 400
$p = New-Object WC+POINT
[void][WC]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 350
[void][WC]::GetCursorPos([ref]$p)
Write-Output ("cursor now " + $p.X + "," + $p.Y)
Shot ("winclick_" + $Button + "_hover.png")
if (-not $NoClick) {
    $down = 0x0002; $up = 0x0004
    if ($Button -eq "right") { $down = 0x0008; $up = 0x0010 }
    [WC]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 70
    [WC]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
    Write-Output ("clicked " + $Button)
    Start-Sleep -Milliseconds 1000
    State ("after " + $Button + " click (+1s)")
    Shot ("winclick_" + $Button + "_after.png")
    Start-Sleep -Milliseconds 900
    State ("after " + $Button + " click (+1.9s)")
    Shot ("winclick_" + $Button + "_after2.png")
    Esc
    Start-Sleep -Milliseconds 500
    State "after esc"
}
