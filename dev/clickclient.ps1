param([int]$X = 100, [int]$Y = 60)
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CC {
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
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
$hw = [CC]::Find('DockStripWindow')
if ($hw -eq [IntPtr]::Zero) { 'no strip'; exit 1 }
$lp = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
[CC]::PostMessage($hw, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 60
[CC]::PostMessage($hw, 0x0202, [IntPtr]0, $lp) | Out-Null
"clicked client $X,$Y"
