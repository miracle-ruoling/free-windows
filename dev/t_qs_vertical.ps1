# Can the quick settings panel's CONTENT be moved vertically by moving its (full-height)
# window off the top of the screen? Also: what window is the media card?
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class QQ7 {
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
[void][QQ7]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([QQ7]::GetSystemMetrics(0)), ([QQ7]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
[QQ7]::Esc(); Start-Sleep -Milliseconds 800
[QQ7]::WinA(); Start-Sleep -Milliseconds 1500
$fg = [QQ7]::GetForegroundWindow()
Write-Output ("panel window: " + [QQ7]::Info($fg))
$r = New-Object QQ7+RECT
[void][QQ7]::GetWindowRect($fg, [ref]$r)
Write-Output "--- media card probe (right side, above the panel content) ---"
foreach ($pt in @(@(1300, 560), @(1380, 600), @(1450, 520))) {
    Write-Output ("  $($pt[0]),$($pt[1]) -> " + [QQ7]::Info([QQ7]::At($pt[0], $pt[1])))
}
Shot "qs7_open.png"
# move the full-height window up so its bottom-anchored content shifts up
[void][QQ7]::SetWindowPos($fg, [IntPtr]::Zero, $r.Left, -441, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 600
Write-Output ("after y=-441: " + [QQ7]::Info($fg))
Shot "qs7_up.png"
[void][QQ7]::SetWindowPos($fg, [IntPtr]::Zero, $r.Left, $r.Top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 300
[QQ7]::Esc(); Start-Sleep -Milliseconds 400
Write-Output "done"
