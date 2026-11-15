# Decisive check: who draws the visible Start panel on this build?
# Opens Start with Ctrl+Esc, screenshots, lists every window hosted by the possible
# Start hosts, and measures the panel's pixel bounds so the two can be compared.
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WX2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowDisplayAffinity(IntPtr h, out uint a);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R;
    public string Show() { return string.Format("h={0} pid={1} vis={2} cls={3} txt='{4}' rect={5},{6} {7}x{8}",
        H.ToInt64(), Pid, Vis, Cls, Txt, R.Left, R.Top, R.Right-R.Left, R.Bottom-R.Top); }
  }
  public static Info One(IntPtr h) {
    Info i = new Info(); i.H = h;
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200); i.Cls = b.ToString();
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200); i.Txt = t.ToString();
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
  public static List<Info> Kids(IntPtr p) {
    List<Info> l = new List<Info>();
    EnumChildWindows(p, delegate(IntPtr h, IntPtr lp) { l.Add(One(h)); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WX2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WX2]::GetSystemMetrics(0)), ([WX2]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WX2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WX2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$hosts = @()
foreach ($n in "SearchHost","StartMenuExperienceHost","ShellHost","ShellExperienceHost","explorer") {
    foreach ($p in (Get-Process $n -ErrorAction SilentlyContinue)) { $hosts += [int]$p.Id }
}
Write-Output ("hosts pids: " + ($hosts -join ','))
Esc; Start-Sleep -Milliseconds 500
[WX2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WX2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WX2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WX2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200
Write-Output ("fg: " + ([WX2]::One([WX2]::GetForegroundWindow())).Show())
Write-Output "--- windows of the candidate hosts (rect width>200) ---"
foreach ($w in ([WX2]::All())) {
    if (($hosts -contains [int]$w.Pid) -and ($w.R.Right - $w.R.Left) -gt 200) {
        Write-Output ("  " + $w.Show())
        foreach ($c in ([WX2]::Kids($w.H) | Where-Object { ($_.R.Right - $_.R.Left) -gt 200 })) {
            Write-Output ("     child " + $c.Show())
        }
    }
}
Shot "who_draws_start.png"
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 400; Write-Output "closed" }
