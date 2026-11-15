# With the panel open: what is the media card, and does resizing the panel window
# re-layout the visible content (a way to move it vertically)?
param([switch]$NoMove)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QQ6 {
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
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
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
  public static IntPtr At(int x, int y) { POINT p; p.X = x; p.Y = y; return GetAncestor(WindowFromPoint(p), 2); }
  public static void WinA() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x41, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x41, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
}
"@
[void][QQ6]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([QQ6]::GetSystemMetrics(0)), ([QQ6]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
[QQ6]::Esc(); Start-Sleep -Milliseconds 700
[QQ6]::WinA(); Start-Sleep -Milliseconds 1400
$fg = [QQ6]::GetForegroundWindow()
Write-Output ("foreground: " + [QQ6]::Info($fg))
$r = New-Object QQ6+RECT
[void][QQ6]::GetWindowRect($fg, [ref]$r)
Write-Output ("probe inside panel (left+50, top+700): " + [QQ6]::Info([QQ6]::At($r.Left + 50, $r.Top + 700)))
foreach ($pt in @(@(1500, 250), @(1600, 350), @(1850, 300), @(1700, 330))) {
    Write-Output ("probe $($pt[0]),$($pt[1]) -> " + [QQ6]::Info([QQ6]::At($pt[0], $pt[1])))
}
Shot "qs6_a.png"
if (-not $NoMove) {
    # resize the window: does the visible panel re-layout inside the new box?
    [void][QQ6]::SetWindowPos($fg, [IntPtr]::Zero, $r.Left, 300, $r.Right - $r.Left, 600,
                              0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 600
    Write-Output ("after resize (y=300 h=600): " + [QQ6]::Info($fg))
    Shot "qs6_resized.png"
    [void][QQ6]::SetWindowPos($fg, [IntPtr]::Zero, $r.Left, $r.Top, $r.Right - $r.Left, $r.Bottom - $r.Top,
                              0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 400
}
[QQ6]::Esc(); Start-Sleep -Milliseconds 400
Write-Output "done"
