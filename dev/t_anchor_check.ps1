# Open Start from the strip's Windows button and capture before/after frames, so the
# panel's real position can be compared with the anchor button (diff the two PNGs with
# dev/shotdiff.py). Prints the button rect and the anchor block content.
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WA3 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static IntPtr Root(int x, int y) { POINT p; p.X = x; p.Y = y; return GetAncestor(WindowFromPoint(p), 2); }
}
"@
[void][WA3]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WA3]::GetSystemMetrics(0)), ([WA3]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WA3]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WA3]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$strip = [WA3]::Find('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output "no strip"; exit 1 }
$r = New-Object WA3+RECT
[void][WA3]::GetWindowRect($strip, [ref]$r)
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
$line = ($txt -split "`r?`n") | Where-Object { $_ -match 'layout: ' } | Select-Object -Last 1
if (-not $line -or $line -notmatch "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { Write-Output ("cannot parse layout: " + $line); exit 1 }
$wl = [int]$Matches[1]; $wt = [int]$Matches[2]; $wr = [int]$Matches[3]; $wb = [int]$Matches[4]
$btn = @{ left = $r.Left + $wl; top = $r.Top + $wt; right = $r.Left + $wr; bottom = $r.Top + $wb }
Write-Output ("strip  " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
Write-Output ("button " + $btn.left + "," + $btn.top + "-" + $btn.right + "," + $btn.bottom)
& (Join-Path $PSScriptRoot 'anchordump.ps1')

Esc; Start-Sleep -Milliseconds 700
Shot "anchor_a.png"
$cx = [int](($btn.left + $btn.right) / 2)
$cy = [int](($btn.top + $btn.bottom) / 2)
[void][WA3]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 350
[WA3]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 70
[WA3]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Write-Output ("clicked the Windows button at " + $cx + "," + $cy)
Start-Sleep -Milliseconds 1300
Shot "anchor_b.png"
$root = [WA3]::Root(600, 300)
$rr = New-Object WA3+RECT
[void][WA3]::GetWindowRect($root, [ref]$rr)
Write-Output ("start host window: h=" + $root.ToInt64() + " rect=" + $rr.Left + "," + $rr.Top + " " + ($rr.Right-$rr.Left) + "x" + ($rr.Bottom-$rr.Top))
Write-Output "saved anchor_a.png / anchor_b.png - diff them for the panel bounds"
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 500 }
