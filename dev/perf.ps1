# What does the dock cost while the strip is being moved?
#   CPU  : this process, as % of one core and of the whole machine
#   GPU  : this process's engines, and the system-wide 3D engine total
# Everything is sampled in the same loop that moves the window, so there is no
# background-job plumbing.
param([int]$Seconds = 8, [int]$Y = 300, [string]$Tag = "run")

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class PF2 {
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
[PF2]::SetProcessDPIAware() | Out-Null
$hw = [PF2]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$r = New-Object RECT
[PF2]::GetWindowRect($hw, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$orig = "$($r.Left),$($r.Top)"
$proc = Get-Process dock
$pidDock = $proc.Id

[PF2]::SetCursorPos(800, $Y + [int]($h / 2)) | Out-Null
Start-Sleep -Milliseconds 400

$gpuSelf = @(); $gpuSys = @()
$lastSample = [DateTime]::MinValue
$cpu0 = $proc.TotalProcessorTime
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $x = 400 + [int](120 * [Math]::Sin($i / 6.0))
    [PF2]::SetWindowPos($hw, [IntPtr]0, $x, $Y, $w, $h, 0x0014) | Out-Null
    Start-Sleep -Milliseconds 15
    $i++
    if (((Get-Date) - $lastSample).TotalMilliseconds -gt 500) {
        $lastSample = Get-Date
        try {
            $s = (Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop).CounterSamples
            $mine = $s | Where-Object { $_.InstanceName -like "*pid_${pidDock}_*" }
            $gpuSelf += ($mine | Measure-Object -Property CookedValue -Sum).Sum
            $sys = $s | Where-Object { $_.InstanceName -like "*engtype_3d*" }
            $gpuSys += ($sys | Measure-Object -Property CookedValue -Sum).Sum
        } catch {}
    }
}
$sw.Stop()
$proc.Refresh()
$cpuSec = ($proc.TotalProcessorTime - $cpu0).TotalSeconds
$p = $orig.Split(',')
[PF2]::SetWindowPos($hw, [IntPtr]0, [int]$p[0], [int]$p[1], $w, $h, 0x0014) | Out-Null

$cores = [Environment]::ProcessorCount
$wall = $sw.Elapsed.TotalSeconds
$oneCore = $cpuSec / $wall * 100
$selfGpu = if ($gpuSelf.Count) { ($gpuSelf | Measure-Object -Average).Average } else { 0 }
$sysGpu = if ($gpuSys.Count) { ($gpuSys | Measure-Object -Average).Average } else { 0 }
$msg = [string]::Format("{0,-10} moves={1,4} wall={2,5:N1}s | CPU {3,5:N1}% of one core ({4:N1}% of {5}) | GPU self {6,4:N1}% | system3D {7,4:N1}%",
    [string]$Tag, [int]$i, [double]$wall, [double]$oneCore, [double]($oneCore / $cores), [int]$cores,
    [double]$selfGpu, [double]$sysGpu)
$msg
