# Quick settings: is the visible panel tied to its window's position?
# Only ever touches a window whose class is ControlCenterWindow (hit-test validated).
param([switch]$NoMove)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QQ3 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static string Info(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    uint pid; GetWindowThreadProcessId(h, out pid);
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    StringBuilder t = new StringBuilder(128); GetWindowText(h, t, 128);
    RECT r; GetWindowRect(h, out r);
    return string.Format("h={0} pid={1} cls={2} txt='{3}' rect={4},{5} {6}x{7}", h.ToInt64(), pid, b, t, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top);
  }
  public static IntPtr At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    return GetAncestor(WindowFromPoint(p), 2);
  }
  public static string ClassOf(IntPtr h) {
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128); return b.ToString();
  }
  public static void OpenWinA() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(70);
    keybd_event(0x41, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x41, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(70);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
}
"@
[void][QQ3]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([QQ3]::GetSystemMetrics(0)), ([QQ3]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
$panel = [IntPtr]::Zero
for ($try = 1; $try -le 4; $try++) {
    [QQ3]::Esc(); Start-Sleep -Milliseconds 500
    [QQ3]::OpenWinA(); Start-Sleep -Milliseconds 1400
    $h = [QQ3]::At(1700, 700)
    if ([QQ3]::ClassOf($h) -eq 'ControlCenterWindow') { $panel = $h; break }
    Write-Output ("try " + $try + ": panel not open (hit=" + [QQ3]::Info($h) + ")")
}
if ($panel -eq [IntPtr]::Zero) { Write-Output "could not open the quick settings panel"; [QQ3]::Esc(); exit 1 }

Write-Output ("panel: " + [QQ3]::Info($panel))
$r = New-Object QQ3+RECT
[void][QQ3]::GetWindowRect($panel, [ref]$r)
Write-Output ("content probe: 1700,300 -> " + [QQ3]::Info([QQ3]::At(1700, 300)))
Write-Output ("content probe: 1500,250 -> " + [QQ3]::Info([QQ3]::At(1500, 250)))
Shot "qs_a.png"
if (-not $NoMove) {
    [void][QQ3]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left, $r.Top + 200, 0, 0,
                              0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 500
    Write-Output ("after +200 y: " + [QQ3]::Info($panel))
    Shot "qs_moved_y.png"
    [void][QQ3]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left + 200, $r.Top, 0, 0,
                              0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 500
    Write-Output ("after +200 x: " + [QQ3]::Info($panel))
    Shot "qs_moved_x.png"
    [void][QQ3]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left, $r.Top, 0, 0,
                              0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 300
}
[QQ3]::Esc()
Start-Sleep -Milliseconds 400
Write-Output "closed"
