param([int]$Seconds = 8, [int]$Y = 300, [string]$Tag = "run")
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class CP {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static IntPtr Find(string cls) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(h, sb, 256);
            if (sb.ToString() == cls) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
[CP]::SetProcessDPIAware() | Out-Null
$hw = [CP]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT; [CP]::GetWindowRect($hw, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$orig = "$($r.Left),$($r.Top)"
$proc = Get-Process dock
[CP]::SetCursorPos(800, $Y + [int]($h / 2)) | Out-Null
Start-Sleep -Milliseconds 400
$c0 = $proc.TotalProcessorTime
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $x = 400 + [int](120 * [Math]::Sin($i / 6.0))
    [CP]::SetWindowPos($hw, [IntPtr]0, $x, $Y, $w, $h, 0x0014) | Out-Null
    Start-Sleep -Milliseconds 15
    $i++
}
$sw.Stop(); $proc.Refresh()
$cpu = ($proc.TotalProcessorTime - $c0).TotalSeconds
$p = $orig.Split(',')
[CP]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], $w, $h, 0x0014) | Out-Null
$cores = [Environment]::ProcessorCount
[RegEx]::Replace(("{0,-12} moves={1} wall={2:N1}s | CPU {3:N1}% of one core ({4:N2}% of {5} cores)" -f `
  $Tag, $i, $sw.Elapsed.TotalSeconds, ($cpu / $sw.Elapsed.TotalSeconds * 100), ($cpu / $sw.Elapsed.TotalSeconds * 100 / $cores), $cores), ',', '.')
