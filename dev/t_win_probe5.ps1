# Recon 5: open Start / Win+X, take the window that gets the foreground, move it, screenshot.
param([switch]$WinX, [switch]$Move)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WD {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R;
    public string Show() { return string.Format("{0} cls={1} txt='{2}' pid={3} vis={4} rect={5},{6} {7}x{8}",
        H, Cls, Txt, Pid, Vis, R.Left, R.Top, R.Right-R.Left, R.Bottom-R.Top); }
  }
  public static Info One(IntPtr h) {
    Info i = new Info(); i.H = h;
    StringBuilder b = new StringBuilder(256); GetClassName(h, b, 256); i.Cls = b.ToString();
    StringBuilder t = new StringBuilder(256); GetWindowText(h, t, 256); i.Txt = t.ToString();
    uint p; GetWindowThreadProcessId(h, out p); i.Pid = p;
    i.Vis = IsWindowVisible(h);
    RECT r; GetWindowRect(h, out r); i.R = r;
    return i;
  }
  public static List<Info> All() {
    List<Info> l = new List<Info>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) { l.Add(One(h)); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WD]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WD]::GetSystemMetrics(0)), ([WD]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output ("shot " + $name)
}
$tag = if ($WinX) { "winx" } else { "start" }
Write-Output ("fg before: " + ([WD]::One([WD]::GetForegroundWindow())).Show())
if ($WinX) {
    [WD]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
    [WD]::keybd_event(0x58, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [WD]::keybd_event(0x58, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
    [WD]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
} else {
    [WD]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
    [WD]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
}
Start-Sleep -Milliseconds 1000
$fg = [WD]::GetForegroundWindow()
$fi = [WD]::One($fg)
Write-Output ("fg after: " + $fi.Show())
# every window of that pid, to see the layer stack
Write-Output ("all windows of pid " + $fi.Pid + ":")
foreach ($w in ([WD]::All() | Where-Object { $_.Pid -eq $fi.Pid })) { Write-Output ("   " + $w.Show()) }
Shot ("win5_" + $tag + "_open.png")
if ($Move) {
    $ok = [WD]::SetWindowPos($fg, [IntPtr]::Zero, $fi.R.Left + 130, $fi.R.Top + 100, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 450
    $f2 = [WD]::One($fg)
    Write-Output ("move ok=$ok -> " + $f2.Show())
    Shot ("win5_" + $tag + "_moved.png")
    $p = New-Object WD+POINT; $p.X = 1000; $p.Y = 600
    $root = [WD]::GetAncestor([WD]::WindowFromPoint($p), 2)
    Write-Output ("hit 1000,600 root: " + ([WD]::One($root)).Show())
    [void][WD]::SetWindowPos($fg, [IntPtr]::Zero, $fi.R.Left, $fi.R.Top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 300
    Write-Output ("restored -> " + ([WD]::One($fg)).R.Left + "," + ([WD]::One($fg)).R.Top)
}
[WD]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
[WD]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
Write-Output ("fg after esc: " + ([WD]::One([WD]::GetForegroundWindow())).Show())
Write-Output ("still alive: " + ([WD]::One($fg)).Show())
