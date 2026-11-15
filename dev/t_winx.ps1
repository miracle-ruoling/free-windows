# Recon: the Win+X (power user) menu - which window is it, and can we move it?
param([switch]$Move)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WM {
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
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R;
    public long Area { get { return (long)(R.Right-R.Left)*(R.Bottom-R.Top); } }
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
[void][WM]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WM]::GetSystemMetrics(0)), ([WM]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WM]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WM]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$before = @{}
foreach ($w in [WM]::All()) { $before[[string]$w.H] = $w }
Esc; Start-Sleep -Milliseconds 300
[WM]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
[WM]::keybd_event(0x58, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WM]::keybd_event(0x58, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
[WM]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
Write-Output ("fg=" + ([WM]::One([WM]::GetForegroundWindow())).Show())
$new = @()
foreach ($w in [WM]::All()) {
    $o = $before[[string]$w.H]
    if ($w.Vis -and (-not $o -or -not $o.Vis)) {
        Write-Output ("NEW " + $w.Show())
        $new += $w
    }
}
Shot "winx_a.png"
if ($Move -and $new.Count -gt 0) {
    $t = $new | Sort-Object Area -Descending | Select-Object -First 1
    Write-Output ("target " + $t.Show())
    $ok = [WM]::SetWindowPos($t.H, [IntPtr]::Zero, $t.R.Left + 400, $t.R.Top - 200, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
    Start-Sleep -Milliseconds 400
    Write-Output ("moved ok=$ok -> " + ([WM]::One($t.H)).Show())
    Shot "winx_b.png"
}
Esc
Start-Sleep -Milliseconds 400
Write-Output "closed"
