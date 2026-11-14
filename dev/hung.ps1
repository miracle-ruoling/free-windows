Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class HG {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern long GetWindowLong(IntPtr h, int idx);
    public static string Probe(IntPtr h) {
        IntPtr res;
        IntPtr r = SendMessageTimeout(h, 0 /*WM_NULL*/, IntPtr.Zero, IntPtr.Zero, 0x0002 /*SMTO_ABORTIFHUNG*/, 800, out res);
        return r == IntPtr.Zero ? "NOT RESPONDING" : "responds";
    }
}
"@
$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { "no dock process"; exit }
"pid=" + $p.Id + "  threads=" + $p.Threads.Count + "  cpu=" + [math]::Round($p.CPU, 1) + "s  responding=" + $p.Responding
[HG]::EnumWindows({ param($h,$lp)
    $procId = 0
    [void][System.Diagnostics.Process]::GetProcessById(0)
    return $true }, [IntPtr]::Zero) | Out-Null
# enumerate this process's windows with class/style
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class HG2 {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern long GetWindowLong(IntPtr h, int idx);
    public static void Dump(uint target) {
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid != target) return true;
            StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, 256);
            long ex = GetWindowLong(h, -20);
            Console.WriteLine("  " + sb.ToString() + " visible=" + IsWindowVisible(h) + " exstyle=0x" + ex.ToString("X"));
            return true;
        }, IntPtr.Zero);
    }
}
"@
"windows:"; [HG2]::Dump([uint32]$p.Id)
"strip responds: " + [HG]::Probe(([HG2]::FindWindow0))
