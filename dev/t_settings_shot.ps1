# Capture the settings panel (optionally after clicking one of its tabs).
#
#   .\t_settings_shot.ps1 -Out dev/x.png                 # just capture
#   .\t_settings_shot.ps1 -Tab 0 -Out dev/x.png          # click tab 0 (全局) first
#   .\t_settings_shot.ps1 -Tab 3 -Out dev/x.png          # click tab 3 (组 1)
#   .\t_settings_shot.ps1 -Close                         # click the × and exit
param([int]$Tab = -1, [string]$Out = 'dev/settings.png', [switch]$Close)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class SetPanel {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls && IsWindowVisible(h)) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    Thread.Sleep(120);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(250);
  }
}
"@
[void][SetPanel]::SetProcessDpiAwarenessContext([IntPtr](-4))
$h = [SetPanel]::Find('DockSettingsWindow')
if ($h -eq [IntPtr]::Zero) { Write-Output 'settings panel is not open'; exit 1 }
$r = New-Object SetPanel+RECT
[void][SetPanel]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
Write-Output ("panel {0},{1} {2}x{3}" -f $r.Left, $r.Top, $w, $hh)
if ($Close) {
    [SetPanel]::Click($r.Left + $w - 40, $r.Top + 36)
    Write-Output 'closed'
    exit 0
}
if ($Tab -ge 0) {
    # tab i: centred in its slice of the tab row (see TabRect in dock.cpp)
    $tabs = 4                       # pages: 全局 / 条 / 托盘 / 组 1  (grows with groups)
    $slice = [int](($w - 52) / $tabs)
    $tx = $r.Left + 26 + $Tab * $slice + [int]($slice / 2)
    $ty = $r.Top + 64 + 22
    [SetPanel]::Click($tx, $ty)
    Write-Output ("clicked tab {0} at {1},{2}" -f $Tab, $tx, $ty)
    [void][SetPanel]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
    Write-Output ("panel now {0},{1} {2}x{3}" -f $r.Left, $r.Top, $w, $hh)
}
$py = "$env:USERPROFILE\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
$x0 = [Math]::Max(0, $r.Left - 6); $y0 = [Math]::Max(0, $r.Top - 6)
$capW = [Math]::Min(1920 - $x0, $w + 12); $capH = [Math]::Min(1080 - $y0, $hh + 12)
& $py -c @"
import ctypes, numpy as np
from PIL import Image
u = ctypes.WinDLL('user32'); g = ctypes.WinDLL('gdi32')
u.SetProcessDPIAware()
x0, y0, w, h = $x0, $y0, $capW, $capH
class BIH(ctypes.Structure):
    _fields_=[('biSize',ctypes.c_uint32),('biWidth',ctypes.c_long),('biHeight',ctypes.c_long),
              ('biPlanes',ctypes.c_uint16),('biBitCount',ctypes.c_uint16),('biCompression',ctypes.c_uint32),
              ('biSizeImage',ctypes.c_uint32),('biXPelsPerMeter',ctypes.c_long),('biYPelsPerMeter',ctypes.c_long),
              ('biClrUsed',ctypes.c_uint32),('biClrImportant',ctypes.c_uint32)]
class BI(ctypes.Structure):
    _fields_=[('h',BIH),('colors',ctypes.c_uint32*3)]
bi = BI(); bi.h.biSize=ctypes.sizeof(BIH); bi.h.biWidth=w; bi.h.biHeight=-h
bi.h.biPlanes=1; bi.h.biBitCount=32; bi.h.biCompression=0
bits = ctypes.c_void_p(); screen = u.GetDC(None)
mdc = g.CreateCompatibleDC(screen)
bmp = g.CreateDIBSection(screen, ctypes.byref(bi), 0, ctypes.byref(bits), None, 0)
g.SelectObject(mdc, bmp); g.BitBlt(mdc,0,0,w,h,screen,x0,y0,0x00CC0020)
a = np.frombuffer(ctypes.string_at(bits, w*h*4), dtype=np.uint8).reshape(h,w,4)[:,:,[2,1,0]]
Image.fromarray(a).save(r'$Out')
print('saved $Out')
"@
