# shared helpers: dot-source this file (no param block, it would clobber the caller's $Out)
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class S {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (string.Equals(b.ToString(), cls, StringComparison.OrdinalIgnoreCase)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static string FgInfo() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    uint pid; GetWindowThreadProcessId(h, out pid);
    return string.Format("fg={0} cls={1} pid={2}", h, b.ToString(), pid);
  }
  public static void MoveTo(int x, int y) { SetCursorPos(x, y); }
  public static void LeftClick() { mouse_event(0x0002,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(0x0004,0,0,0,UIntPtr.Zero); }
  public static void RightClick() { mouse_event(0x0008,0,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(0x0010,0,0,0,UIntPtr.Zero); }
}
"@
[void][S]::SetProcessDPIAware()
$global:DevHere = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-State($tag) {
  $strip = [S]::ByClass('DockStripWindow')
  $grid = [S]::ByClass('DockGridWindow')
  $gv = ($grid -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($grid)
  $p = New-Object S+POINT
  [void][S]::GetCursorPos([ref]$p)
  Write-Output ("[{0}] gridVisible={1} cursor={2},{3} {4}" -f $tag, $gv, $p.X, $p.Y, [S]::FgInfo())
}

function Open-Grid() {
  $strip = [S]::ByClass('DockStripWindow')
  $grid = [S]::ByClass('DockGridWindow')
  if (($grid -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($grid)) { return $true }
  $c = New-Object S+RECT
  [void][S]::GetClientRect($strip, [ref]$c)
  $y = [int]($c.Bottom / 2)
  foreach ($n in 40,56,72,88,104,120,136,152,168,184,200) {
    $x = $c.Right - $n
    $p = New-Object S+POINT
    $p.X = $x; $p.Y = $y
    [void][S]::ClientToScreen($strip, [ref]$p)
    [void][S]::SetCursorPos($p.X, $p.Y)
    Start-Sleep -Milliseconds 300
    $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
    [void][S]::SendMessage($strip, 0x0201, [IntPtr]1, $lp)
    Start-Sleep -Milliseconds 50
    [void][S]::SendMessage($strip, 0x0202, [IntPtr]0, $lp)
    Start-Sleep -Milliseconds 400
    $grid = [S]::ByClass('DockGridWindow')
    if (($grid -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($grid)) { Write-Output ("opened with chevron client x=" + $x); return $true }
  }
  return $false
}

function Shot($name) {
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object System.Drawing.Bitmap 1920, 1080
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1920, 1080))
  $g.Dispose()
  $bmp.Save((Join-Path $global:DevHere $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

function Wait-Idle([int]$StableMs = 1500, [int]$TimeoutSec = 90) {
  # The machine is shared with the user: only start an injected-input test when the
  # physical mouse has been still and released for a moment.
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastX = -1; $lastY = -1; $stillSince = Get-Date
  while ((Get-Date) -lt $deadline) {
    $p = New-Object S+POINT
    [void][S]::GetCursorPos([ref]$p)
    $lp = [S]::GetAsyncKeyState(0x01)
    $rp = [S]::GetAsyncKeyState(0x02)
    $busy = (($lp -band 0x8000) -ne 0) -or (($rp -band 0x8000) -ne 0)
    if ($busy -or $p.X -ne $lastX -or $p.Y -ne $lastY) {
      $stillSince = Get-Date; $lastX = $p.X; $lastY = $p.Y
    } elseif (((Get-Date) - $stillSince).TotalMilliseconds -ge $StableMs) {
      return $true
    }
    Start-Sleep -Milliseconds 60
  }
  return $false
}

function Get-LogLines() {
  $p = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
  try {
    $fs = New-Object System.IO.FileStream($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
    return ($txt -split "`r?`n")
  } catch { return @() }
}

# Map "grid cell index -> exe" from the dock log. The grid paints g_tray sorted by tip,
# and BuildTray logs "tray[i] tip='..' exe=..". Never assume a fixed order: it changes
# whenever an app registers or drops an icon.
function Get-TrayCellMap() {
  $lines = Get-LogLines
  $map = @{}
  $anchor = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match 'icons from the bridge') { $anchor = $i; break }
  }
  if ($anchor -lt 0) { return $map }
  for ($i = $anchor - 1; $i -ge 0; $i--) {
    $m = [regex]::Match($lines[$i], "tray\[(\d+)\] tip='[^']*' exe=([^ ]+)")
    if (-not $m.Success) { break }
    $map[[int]$m.Groups[1].Value] = $m.Groups[2].Value
  }
  return $map
}

function Get-CellForExe([string]$needle) {
  $map = Get-TrayCellMap
  foreach ($k in ($map.Keys | Sort-Object)) {
    if ($map[$k].ToLower().Contains($needle.ToLower())) { return $k }
  }
  return -1
}

function Get-LastMenuRect() {
  $lines = Get-LogLines
  $x = -1; $y = -1; $w = 0; $h = 0
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    $m = [regex]::Match($l, 'appeared at (-?\d+),(-?\d+) \((\d+)x(\d+)\)')
    if ($m.Success -and $x -lt 0) {
      $x = [int]$m.Groups[1].Value; $y = [int]$m.Groups[2].Value
      $w = [int]$m.Groups[3].Value; $h = [int]$m.Groups[4].Value
    }
    $m2 = [regex]::Match($l, 'moved the menu itself to (-?\d+),(-?\d+)')
    if ($m2.Success) { $x = [int]$m2.Groups[1].Value; $y = [int]$m2.Groups[2].Value; break }
  }
  if ($x -lt 0) { return $null }
  return @($x, $y, $w, $h)
}
