param(
  [int]$Cell = 2,
  [int]$Dx = 0,
  [int]$Dy = -120,
  [string]$Out = 'menutest.png',
  [int]$Settle = 700,
  [switch]$NoClick
)
# Feasibility probe: right-click one grid cell, find the app's popup menu window, then
# try to MOVE that window with SetWindowPos instead of moving the mouse cursor.
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class M {
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static List<IntPtr> Visible() {
    List<IntPtr> l = new List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) { if (IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (string.Equals(Cls(h), cls, StringComparison.OrdinalIgnoreCase)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static string Cls(IntPtr h) { StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128); return b.ToString(); }
  public static string Txt(IntPtr h) { StringBuilder b = new StringBuilder(256); GetWindowText(h, b, 256); return b.ToString(); }
  public static string Desc(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    return string.Format("{0} cls={1} style=0x{2:X} rect={3},{4}-{5},{6} ({7}x{8}) title='{9}'",
      h, Cls(h), GetWindowLong(h, -16), r.Left, r.Top, r.Right, r.Bottom, r.Right-r.Left, r.Bottom-r.Top, Txt(h));
  }
  // mouse_event has no DPI virtualisation for absolute coordinates once the process is
  // DPI aware, so this moves the real pointer exactly where we ask.
  public static void MoveTo(int x, int y) {
    int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
    mouse_event(0x8001, (int)((long)x * 65535 / (w - 1)), (int)((long)y * 65535 / (h - 1)), 0, UIntPtr.Zero);
  }
  public static void RightClick() {
    mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(90);
    mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);
  }
  public static void LeftClick() {
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(90);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
"@
[void][M]::SetProcessDPIAware()

$strip = [M]::ByClass("DockStripWindow")
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no strip window'; exit 1 }
$grid = [M]::ByClass("DockGridWindow")
$open = ($grid -ne [IntPtr]::Zero) -and [M]::IsWindowVisible($grid)

if (-not $open) {
  $c = New-Object M+RECT
  [void][M]::GetClientRect($strip, [ref]$c)
  $y = [int]($c.Bottom / 2)
  foreach ($n in 40,56,72,88,104,120,136,152,168,184,200) {
    $x = $c.Right - $n
    $p = New-Object M+POINT
    $p.X = $x; $p.Y = $y
    [void][M]::ClientToScreen($strip, [ref]$p)
    [M]::MoveTo($p.X, $p.Y)
    Start-Sleep -Milliseconds 350
    $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
    [void][M]::SendMessage($strip, 0x0201, [IntPtr]1, $lp)
    Start-Sleep -Milliseconds 60
    [void][M]::SendMessage($strip, 0x0202, [IntPtr]0, $lp)
    Start-Sleep -Milliseconds 450
    $grid = [M]::ByClass("DockGridWindow")
    if ($grid -ne [IntPtr]::Zero -and [M]::IsWindowVisible($grid)) { Write-Output ("grid opened, chevron client x=" + $x); break }
  }
  if ($grid -eq [IntPtr]::Zero) { Write-Output 'grid did not open'; exit 1 }
}

$gr = New-Object M+RECT
[void][M]::GetWindowRect($grid, [ref]$gr)
$gw = $gr.Right - $gr.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($Cell / $cols); $col = $Cell % $cols
$cx = $gr.Left + 14 + $col * 66 + 30
$cy = $gr.Top + 14 + $row * 66 + 30
Write-Output ("grid {0},{1} {2}x{3} cols={4} cell {5} -> {6},{7}" -f $gr.Left,$gr.Top,$gw,($gr.Bottom-$gr.Top),$cols,$Cell,$cx,$cy)

$before = @{}
foreach ($h in [M]::Visible()) { $before[[int64]$h] = $true }

[M]::MoveTo($cx, $cy)
Start-Sleep -Milliseconds 350
$c0 = New-Object M+POINT
[void][M]::GetCursorPos([ref]$c0)
if (-not $NoClick) { [M]::RightClick() }

$menu = [IntPtr]::Zero
for ($i = 0; $i -lt 80; $i++) {
  Start-Sleep -Milliseconds 20
  foreach ($h in [M]::Visible()) {
    if ($before.ContainsKey([int64]$h)) { continue }
    $r = New-Object M+RECT
    [void][M]::GetWindowRect($h, [ref]$r)
    if (($r.Right - $r.Left) -lt 40 -or ($r.Bottom - $r.Top) -lt 20) { continue }
    if ([M]::Cls($h) -eq 'DockGridWindow') { continue }
    $menu = $h; break
  }
  if ($menu -ne [IntPtr]::Zero) { break }
}
$c1 = New-Object M+POINT
[void][M]::GetCursorPos([ref]$c1)
Write-Output ("cursor before={0},{1} after={2},{3}" -f $c0.X,$c0.Y,$c1.X,$c1.Y)
if ($menu -eq [IntPtr]::Zero) { Write-Output 'no new popup window appeared'; exit 2 }
Write-Output ("new window: " + [M]::Desc($menu))

Start-Sleep -Milliseconds $Settle
$r0 = New-Object M+RECT
[void][M]::GetWindowRect($menu, [ref]$r0)
Write-Output ("settled: {0},{1} {2}x{3}" -f $r0.Left,$r0.Top,($r0.Right-$r0.Left),($r0.Bottom-$r0.Top))

$ok = [M]::SetWindowPos($menu, [IntPtr]::Zero, $r0.Left + $Dx, $r0.Top + $Dy, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Start-Sleep -Milliseconds 250
$r1 = New-Object M+RECT
[void][M]::GetWindowRect($menu, [ref]$r1)
Write-Output ("SetWindowPos({0},{1}) ok={2} err={3} -> now {4},{5} {6}x{7}" -f $Dx,$Dy,$ok,$err,$r1.Left,$r1.Top,($r1.Right-$r1.Left),($r1.Bottom-$r1.Top))

Add-Type -AssemblyName System.Drawing
$w = [M]::GetSystemMetrics(0); $h = [M]::GetSystemMetrics(1)
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save((Join-Path $here $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("saved " + $Out)

$lp2 = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
try {
  $fs = New-Object System.IO.FileStream($lp2, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
  $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
  $lines = $txt -split "`r?`n"
  $lines[([Math]::Max(0, $lines.Count - 16))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:' } | ForEach-Object { Write-Output ("LOG " + $_) }
} catch { Write-Output ("log read failed: " + $_.Exception.Message) }
