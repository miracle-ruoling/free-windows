# What is on screen while Start is open? List every window with a large area or a
# CoreWindow class, with process names, plus the foreground window.
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WZ2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R; public int Style;
    public long Area { get { return (long)(R.Right-R.Left)*(R.Bottom-R.Top); } }
    public string Show() { return string.Format("h={0} pid={1} vis={2} cls={3} txt='{4}' rect={5},{6} {7}x{8} style=0x{9:X8}",
        H.ToInt64(), Pid, Vis, Cls, Txt, R.Left, R.Top, R.Right-R.Left, R.Bottom-R.Top, Style); }
  }
  public static Info One(IntPtr h) {
    Info i = new Info(); i.H = h;
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200); i.Cls = b.ToString();
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200); i.Txt = t.ToString();
    uint p; GetWindowThreadProcessId(h, out p); i.Pid = p;
    i.Vis = IsWindowVisible(h);
    RECT r; GetWindowRect(h, out r); i.R = r;
    i.Style = GetWindowLong(h, -16);
    return i;
  }
  public static List<Info> All() {
    List<Info> l = new List<Info>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) { l.Add(One(h)); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WZ2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WZ2]::GetSystemMetrics(0)), ([WZ2]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WZ2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WZ2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
function ExeName($p) { try { (Get-Process -Id $p -ErrorAction Stop).ProcessName } catch { "?" } }
Esc; Start-Sleep -Milliseconds 600
[WZ2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WZ2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WZ2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WZ2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300
Write-Output ("fg: " + ([WZ2]::One([WZ2]::GetForegroundWindow())).Show())
$all = [WZ2]::All()
Write-Output ("enumerated=" + $all.Count)
Write-Output "--- windows with area > 1.0M or class containing CoreWindow ---"
foreach ($w in $all) {
    if ($w.Area -gt 1000000 -or $w.Cls -like "*CoreWindow*") {
        Write-Output ("  " + $w.Show() + " exe=" + (ExeName $w.Pid))
    }
}
$p1 = New-Object WZ2+POINT; $p1.X = 600; $p1.Y = 300
$root = [WZ2]::GetAncestor([WZ2]::WindowFromPoint($p1), 2)
Write-Output ("hit 600,300 -> " + ([WZ2]::One($root)).Show() + " exe=" + (ExeName ([WZ2]::One($root)).Pid))
Shot "while_start.png"
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 400; Write-Output "closed" }
