# If we nudge the Start host window, does the shell put it back on the next open?
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class WD2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Root(int x, int y) { POINT p; p.X = x; p.Y = y; return GetAncestor(WindowFromPoint(p), 2); }
}
"@
[void][WD2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Esc {
    [WD2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WD2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
function OpenStart {
    [WD2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [WD2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [WD2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [WD2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 1300
}
function Report([string]$tag) {
    $script:hh = [WD2]::Root(600, 300)
    $script:rr = New-Object WD2+RECT
    [void][WD2]::GetWindowRect($script:hh, [ref]$script:rr)
    Write-Output ("  [$tag] h=" + $script:hh.ToInt64() + " rect=" + $script:rr.Left + "," + $script:rr.Top + " " + ($script:rr.Right-$script:rr.Left) + "x" + ($script:rr.Bottom-$script:rr.Top))
}
Esc; Start-Sleep -Milliseconds 700
Report "closed"
OpenStart
Report "open #1"
[void][WD2]::SetWindowPos($script:hh, [IntPtr]::Zero, $script:rr.Left + 120, $script:rr.Top + 90, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 400
Report "open #1 moved"
Esc; Start-Sleep -Milliseconds 900
Report "closed again"
OpenStart
Report "open #2 (shell reset?)"
Esc; Start-Sleep -Milliseconds 500
