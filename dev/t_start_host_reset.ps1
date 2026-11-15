# Put the Start menu's host window back where the shell expects it (0,0) - my earlier
# experiment left it at +120,+90 and the shell does not reset it.
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class WR3 {
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
[void][WR3]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Esc {
    [WR3]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WR3]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
Esc; Start-Sleep -Milliseconds 600
[WR3]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR3]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR3]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR3]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300
# probe a point inside the panel (it may be offset, so try a few)
foreach ($pt in @(@(600,300), @(720,420), @(900,500))) {
    $h = [WR3]::Root($pt[0], $pt[1])
    $r = New-Object WR3+RECT
    if (-not [WR3]::GetWindowRect($h, [ref]$r)) { continue }
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    if ($w -lt 1000 -or $ht -lt 500) { continue }
    Write-Output ("host h=" + $h.ToInt64() + " at " + $r.Left + "," + $r.Top + " " + $w + "x" + $ht)
    if ($r.Left -ne 0 -or $r.Top -ne 0) {
        $ok = [WR3]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
        Start-Sleep -Milliseconds 300
        [void][WR3]::GetWindowRect($h, [ref]$r)
        Write-Output ("restored ok=$ok -> " + $r.Left + "," + $r.Top)
    }
    break
}
Esc; Start-Sleep -Milliseconds 500
Write-Output "done"
