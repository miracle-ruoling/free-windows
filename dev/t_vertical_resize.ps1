# Does a tall strip survive the mouse release in the fully transparent look?
# Drags the bottom-right corner to make the strip tall, then prints the resulting rect and
# the dock's shrink/layout log lines. The original [dock] x/y/w/h in dock.ini is backed up
# and restored at the end (a restart applies it again).
param([switch]$NoRestore)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WS4 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
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
}
"@
[void][WS4]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WS4]::GetSystemMetrics(0)), ([WS4]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Rect {
    $h = [WS4]::Find('DockStripWindow')
    $r = New-Object WS4+RECT
    [void][WS4]::GetWindowRect($h, [ref]$r)
    return ("{0},{1} {2}x{3}" -f $r.Left, $r.Top, ($r.Right-$r.Left), ($r.Bottom-$r.Top))
}
$ini = "$env:LOCALAPPDATA\Programs\Dock\dock.ini"
$before = @{}
foreach ($k in 'x', 'y', 'w', 'h') {
    $m = Select-String -Path $ini -Pattern ("^" + $k + "=(-?\d+)") | Select-Object -First 1
    if ($m) { $before[$k] = [int]$m.Matches[0].Groups[1].Value }
}
Write-Output ("ini before: " + ($before.Keys | ForEach-Object { $_ + '=' + $before[$_] }) -join ' ')
Write-Output ("strip before: " + (Rect))
Write-Output ("cursor at " + (Get-Process -Id $PID).Id)

$h = [WS4]::Find('DockStripWindow')
$r = New-Object WS4+RECT
[void][WS4]::GetWindowRect($h, [ref]$r)
$pad = 10
$gx = $r.Right - 8      # inside the right edge band
$gy = $r.Bottom - 8     # inside the bottom edge band -> corner zone
$tx = $r.Right - 8 - 520
$ty = $r.Bottom - 8 + 560
[void][WS4]::SetCursorPos($gx, $gy)
Start-Sleep -Milliseconds 300
[WS4]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)   # left down on the corner
Start-Sleep -Milliseconds 120
for ($i = 1; $i -le 12; $i++) {
    $x = [int]($gx + ($tx - $gx) * $i / 12)
    $y = [int]($gy + ($ty - $gy) * $i / 12)
    [void][WS4]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 60
}
Start-Sleep -Milliseconds 200
Write-Output ("during drag: " + (Rect))
Shot "vertical_during.png"
[WS4]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)   # release
Start-Sleep -Milliseconds 800
Write-Output ("after release: " + (Rect))
Shot "vertical_after.png"
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
($txt -split "`r?`n") | Where-Object { $_ -match 'shrink:|layout:' } | Select-Object -Last 4 | ForEach-Object { Write-Output ("  " + $_) }

if (-not $NoRestore) {
    $content = Get-Content $ini -Raw
    foreach ($k in $before.Keys) {
        $content = [regex]::Replace($content, "(?m)^" + $k + "=-?\d+", ($k + "=" + $before[$k]))
    }
    # no BOM (pit 24): UTF8 without BOM
    [System.IO.File]::WriteAllText($ini, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "ini restored (restart the dock to apply)"
}
