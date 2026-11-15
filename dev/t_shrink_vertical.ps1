# Verify the shrink-to-icons step on a tall strip without needing a real drag:
# set the window tall from outside, start+finish a resize (posted messages), and see which
# orientation the dock snaps to. Old code used the ini key (always horizontal).
param([switch]$NoRestore)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class WU4 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
}
"@
[void][WU4]::SetProcessDpiAwarenessContext([IntPtr](-4))
$ini = "$env:LOCALAPPDATA\Programs\Dock\dock.ini"
$before = @{}
foreach ($k in 'x', 'y', 'w', 'h') {
    $m = Select-String -Path $ini -Pattern ("^" + $k + "=(-?\d+)") | Select-Object -First 1
    if ($m) { $before[$k] = [int]$m.Matches[0].Groups[1].Value }
}
$h = [WU4]::Find('DockStripWindow')
$r = [WU4]::Rect($h)
Write-Output ("before: " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))

# a tall, arbitrary shape (this is what the user ends up with right before releasing)
[void][WU4]::SetWindowPos($h, [IntPtr]::Zero, 400, 150, 200, 600, 0x0004 -bor 0x0010)
Start-Sleep -Milliseconds 400
$t = [WU4]::Rect($h)
Write-Output ("tall shape: " + $t.Left + "," + $t.Top + " " + ($t.Right-$t.Left) + "x" + ($t.Bottom-$t.Top))

# start a resize on its bottom edge, then finish it: the release path calls ShrinkToIcons()
$cx = [int](($t.Right - $t.Left) / 2)
$cy = ($t.Bottom - $t.Top) - 8
$lp = [IntPtr]([int64]($cy -shl 16) -bor $cx)
[void][WU4]::SetCursorPos($t.Left + $cx, $t.Top + 20)
Start-Sleep -Milliseconds 200
[void][WU4]::PostMessage($h, 0x0201, [IntPtr]1, $lp)
Start-Sleep -Milliseconds 150
[void][WU4]::PostMessage($h, 0x0202, [IntPtr]0, $lp)
Start-Sleep -Milliseconds 900
$a = [WU4]::Rect($h)
Write-Output ("after release: " + $a.Left + "," + $a.Top + " " + ($a.Right-$a.Left) + "x" + ($a.Bottom-$a.Top))
$vertical = ($a.Bottom - $a.Top) -gt ($a.Right - $a.Left)
Write-Output ("=> " + $(if ($vertical) { "VERTICAL (fix works)" } else { "still horizontal (bug remains)" }))

$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
($txt -split "`r?`n") | Where-Object { $_ -match 'shrink:|resize start|layout:' } | Select-Object -Last 5 | ForEach-Object { Write-Output ("  " + $_) }

if (-not $NoRestore) {
    $content = Get-Content $ini -Raw
    foreach ($k in $before.Keys) {
        $content = [regex]::Replace($content, "(?m)^" + $k + "=-?\d+", ($k + "=" + $before[$k]))
    }
    [System.IO.File]::WriteAllText($ini, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "ini restored (restart the dock to apply)"
}
