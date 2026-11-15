# Confirm the Start panel is XAML inside StartMenuExperienceHost's full-work-area window:
# find that window by hit-testing inside the panel, move it, diff the screenshots.
param([int]$Dx = 120, [int]$Dy = 90)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WA2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string One(IntPtr h) {
    uint p; GetWindowThreadProcessId(h, out p);
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
    RECT r; GetWindowRect(h, out r);
    return string.Format("h={0} pid={1} cls={2} txt='{3}' rect={4},{5} {6}x{7}",
      h.ToInt64(), p, b, t, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top);
  }
  public static IntPtr Root(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    return GetAncestor(WindowFromPoint(p), 2);
  }
}
"@
[void][WA2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WA2]::GetSystemMetrics(0)), ([WA2]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WA2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WA2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
Esc; Start-Sleep -Milliseconds 600
[WA2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WA2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WA2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WA2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300
$root = [WA2]::Root(600, 300)
Write-Output ("root at 600,300: " + [WA2]::One($root))
$r = New-Object WA2+RECT
[void][WA2]::GetWindowRect($root, [ref]$r)
Shot "smehmove_a.png"
$ok = [WA2]::SetWindowPos($root, [IntPtr]::Zero, $r.Left + $Dx, $r.Top + $Dy, 0, 0,
                          0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 500
Write-Output ("moved ok=$ok -> " + [WA2]::One($root))
Shot "smehmove_b.png"
[void][WA2]::SetWindowPos($root, [IntPtr]::Zero, $r.Left, $r.Top, 0, 0,
                          0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 400
Write-Output ("restored -> " + [WA2]::One($root))
Esc; Start-Sleep -Milliseconds 400
