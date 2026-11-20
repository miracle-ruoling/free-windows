# Drag the strip sideways and back (net position unchanged), optionally screenshotting mid-drag.
#
#   .\t_glassdrag.ps1 -Dx 400 -Steps 30 -Shot mid.png
#
# Written for the H3c work: it grabs the strip well inside its body (never an edge, so it moves
# instead of resizing - dev/t_dragperf.ps1 resizes and only restores the position), holds the
# button down for the whole trip, and releases where it started.
param(
    [int]$Dx = 400,
    [int]$Steps = 30,
    [int]$StepMs = 12,
    [string]$Shot = '',
    [int]$SettleMs = 500
)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public class GD {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
}
"@
[void][GD]::SetProcessDpiAwarenessContext([IntPtr](-4))

$strip = [GD]::Find('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'strip not found'; exit 1 }
$r = New-Object GD+RECT
[void][GD]::GetWindowRect($strip, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
Write-Output ("strip {0},{1} {2}x{3}" -f $r.Left, $r.Top, $w, $h)

# Grab in the LEFT padding band at mid height: not an icon (that starts an icon reorder), not the
# top/bottom band (that is the resize edge - grabbing there *scales* the group, which is what made
# this probe look like it "did not move").
$x0 = $r.Left + 5
$y0 = $r.Top + [int]($h / 2)

function Shot([string]$name) {
    if (-not $name) { return }
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("saved " + $name)
}

# hover first so the strip is fully lit before the button goes down
[void][GD]::SetCursorPos($x0, $y0); Start-Sleep -Milliseconds 350
[GD]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)     # LEFTDOWN
Start-Sleep -Milliseconds 80
for ($i = 1; $i -le $Steps; $i++) {
    [void][GD]::SetCursorPos($x0 + [int]([long]$Dx * $i / $Steps), $y0)
    Start-Sleep -Milliseconds $StepMs
    if ($i -eq [int]($Steps / 2)) { Shot $Shot }
}
Start-Sleep -Milliseconds 200
for ($i = $Steps; $i -ge 0; $i--) {
    [void][GD]::SetCursorPos($x0 + [int]([long]$Dx * $i / $Steps), $y0)
    Start-Sleep -Milliseconds $StepMs
}
Start-Sleep -Milliseconds 150
[GD]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)     # LEFTUP
Start-Sleep -Milliseconds $SettleMs

$r2 = New-Object GD+RECT
[void][GD]::GetWindowRect($strip, [ref]$r2)
Write-Output ("after: {0},{1} {2}x{3}  (moved {4},{5})" -f $r2.Left, $r2.Top,
              ($r2.Right - $r2.Left), ($r2.Bottom - $r2.Top),
              ($r2.Left - $r.Left), ($r2.Top - $r.Top))
