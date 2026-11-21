# Can each corner of the group frame start a resize? (user report 2026-11-21: "组框角上的尺寸缩放
# 难以触发，似乎只有一个像素的区域可以触发")
#
#   .\t_corner_grab.ps1 [-Inset 5] [-Drag 25]
#
# For every corner: press `Inset` px inside it, drag `Drag` px outward, release, and report whether
# the frame actually got bigger/smaller. A layered window is hit-tested through its alpha, so this
# is the only honest test - WindowFromPoint lies about 1.6 %-alpha pixels.
param([int]$Inset = 5, [int]$Drag = 25)
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public class CG {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr FindVisibleBox() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == "DockGroupBoxWindow" && IsWindowVisible(h)) {
        RECT r; GetWindowRect(h, out r);
        if (r.Right - r.Left > 40) { found = h; return false; }
      }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static IntPtr FindStrip() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == "DockStripWindow") { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static string R(IntPtr h) { RECT r; GetWindowRect(h, out r);
    return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top); }
  public static bool Drag(int fromX, int fromY, int dx, int dy, int steps) {
    SetCursorPos(fromX, fromY); Thread.Sleep(220);
    RECT before; GetWindowRect(FindVisibleBox(), out before);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(70);
    for (int i = 1; i <= steps; i++) {
      SetCursorPos(fromX + (int)((long)dx * i / steps), fromY + (int)((long)dy * i / steps));
      Thread.Sleep(18);
    }
    Thread.Sleep(120);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(320);
    RECT after; GetWindowRect(FindVisibleBox(), out after);
    int dw = (after.Right - after.Left) - (before.Right - before.Left);
    int dh = (after.Bottom - after.Top) - (before.Bottom - before.Top);
    return (dw != 0 || dh != 0);
  }
}
'@
[void][CG]::SetProcessDpiAwarenessContext([IntPtr](-4))

$box = [CG]::FindVisibleBox()
if ($box -eq [IntPtr]::Zero) {
    # the frame only exists while the pointer is at the group: park it on the strip first
    $strip = [CG]::FindStrip()
    if ($strip -ne [IntPtr]::Zero) {
        $sr = New-Object CG+RECT; [void][CG]::GetWindowRect($strip, [ref]$sr)
        [void][CG]::SetCursorPos([int](($sr.Left + $sr.Right) / 2), [int](($sr.Top + $sr.Bottom) / 2))
        Start-Sleep -Milliseconds 700
        $box = [CG]::FindVisibleBox()
    }
}
if ($box -eq [IntPtr]::Zero) { Write-Output 'no visible group frame - park the pointer on the group first'; exit 1 }
$r = New-Object CG+RECT; [void][CG]::GetWindowRect($box, [ref]$r)
Write-Output ("frame " + [CG]::R($box))

# hover first so the frame/companion are lit
[void][CG]::SetCursorPos([int](($r.Left + $r.Right) / 2), [int](($r.Top + $r.Bottom) / 2))
Start-Sleep -Milliseconds 600
$box = [CG]::FindVisibleBox(); [void][CG]::GetWindowRect($box, [ref]$r)

$cases = @(
    @{ name = 'TL'; x = $r.Left + $Inset;  y = $r.Top + $Inset;    dx = -$Drag; dy = -$Drag },
    @{ name = 'TR'; x = $r.Right - $Inset; y = $r.Top + $Inset;    dx =  $Drag; dy = -$Drag },
    @{ name = 'BL'; x = $r.Left + $Inset;  y = $r.Bottom - $Inset; dx = -$Drag; dy =  $Drag },
    @{ name = 'BR'; x = $r.Right - $Inset; y = $r.Bottom - $Inset; dx =  $Drag; dy =  $Drag }
)
foreach ($c in $cases) {
    $ok = [CG]::Drag($c.x, $c.y, $c.dx, $c.dy, 10)
    # put it back: drag the opposite way from the same corner
    $box = [CG]::FindVisibleBox(); if ($box -eq [IntPtr]::Zero) { Write-Output ($c.name + ': frame disappeared'); continue }
    [void][CG]::GetWindowRect($box, [ref]$r)
    if ($ok) {
        $x2 = if ($c.dx -lt 0) { $r.Left + $Inset } else { $r.Right - $Inset }
        $y2 = if ($c.dy -lt 0) { $r.Top + $Inset } else { $r.Bottom - $Inset }
        [void][CG]::Drag($x2, $y2, -$c.dx, -$c.dy, 10)
    }
    Write-Output ("{0} @{1},{2}: resize started = {3}" -f $c.name, $c.x, $c.y, $ok)
}
