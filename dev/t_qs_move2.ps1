# Open quick settings through the dock's tray bar (the path that works), then test whether
# moving the panel's window moves the visible panel.
param([switch]$NoMove)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QQ4 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
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
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
}
"@
[void][QQ4]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([QQ4]::GetSystemMetrics(0)), ([QQ4]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
$bar = [QQ4]::Find('DockTrayBarWindow')
if ($bar -eq [IntPtr]::Zero) { Write-Output "no tray bar"; exit 1 }
$br = New-Object QQ4+RECT
[void][QQ4]::GetWindowRect($bar, [ref]$br)
Write-Output ("tray bar: " + [QQ4]::Info($bar))

[QQ4]::Esc(); Start-Sleep -Milliseconds 600
# hover the strip first so the tray bar appears, then click its first cell
$strip = [QQ4]::Find('DockStripWindow')
$sr = New-Object QQ4+RECT
[void][QQ4]::GetWindowRect($strip, [ref]$sr)
[void][QQ4]::SetCursorPos($sr.Left + 40, ($sr.Top + $sr.Bottom) / 2)
Start-Sleep -Milliseconds 500
[void][QQ4]::SetCursorPos($br.Left + 40, ($br.Top + $br.Bottom) / 2)
Start-Sleep -Milliseconds 300
[QQ4]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 70
[QQ4]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300

$panel = [QQ4]::At(1700, 700)
if ([QQ4]::ClassOf($panel) -ne 'ControlCenterWindow') {
    Write-Output ("panel not open (hit=" + [QQ4]::Info($panel) + ")")
    exit 1
}
Write-Output ("panel: " + [QQ4]::Info($panel))
Write-Output ("probe 1700,300 (media card area): " + [QQ4]::Info([QQ4]::At(1700, 300)))
$r = New-Object QQ4+RECT
[void][QQ4]::GetWindowRect($panel, [ref]$r)
Shot "qs_a.png"
if (-not $NoMove) {
    [void][QQ4]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left, $r.Top + 200, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 500
    Shot "qs_moved_y.png"
    Write-Output ("after +200 y -> " + [QQ4]::Info($panel))
    [void][QQ4]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left + 200, $r.Top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 500
    Shot "qs_moved_x.png"
    Write-Output ("after +200 x -> " + [QQ4]::Info($panel))
    [void][QQ4]::SetWindowPos($panel, [IntPtr]::Zero, $r.Left, $r.Top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
}
[QQ4]::Esc()
Start-Sleep -Milliseconds 400
Write-Output "done"
