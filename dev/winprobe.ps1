Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class WP {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern long GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    public static void Dump(uint target) {
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid != target) return true;
            StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, 256);
            RECT r; GetWindowRect(h, out r);
            long ex = GetWindowLong(h, -20);
            string flags = "";
            if ((ex & 0x20) != 0) flags += " WS_EX_TRANSPARENT";
            if ((ex & 0x80000) != 0) flags += " WS_EX_LAYERED";
            if ((ex & 0x8) != 0) flags += " WS_EX_TOPMOST";
            Console.WriteLine("  {0} vis={1} rect={2},{3}-{4},{5} ex=0x{6:X}{7}",
                sb.ToString(), IsWindowVisible(h), r.Left, r.Top, r.Right, r.Bottom, ex, flags);
            return true;
        }, IntPtr.Zero);
    }
}
"@
$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { "no dock"; exit }
"pid=" + $p.Id
[WP]::Dump([uint32]$p.Id)
