Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class N {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr hrgn, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr FindBig(StringBuilder needle) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(256); GetWindowText(h, t, 256);
      if (!t.ToString().Contains(needle.ToString())) return true;
      RECT r; GetWindowRect(h, out r);
      if (r.Right - r.Left < 400) return true;
      found = h;
      return false;
    }, IntPtr.Zero);
    return found;
  }
}
"@
$needle = New-Object System.Text.StringBuilder "DeepSeek Harness"
$h = [N]::FindBig($needle)
Write-Output ("target " + $h + " iconic=" + [N]::IsIconic($h))
if ($h -ne [IntPtr]::Zero) {
  [void][N]::ShowWindow($h, 7)
  Start-Sleep -Milliseconds 300
  [void][N]::ShowWindow($h, 9)
  [void][N]::SetForegroundWindow($h)
  Write-Output 'nudged'
}
[void][N]::RedrawWindow([N]::GetDesktopWindow(), [IntPtr]::Zero, [IntPtr]::Zero, 0x0001 -bor 0x0080 -bor 0x0100)
Write-Output 'redraw done'
