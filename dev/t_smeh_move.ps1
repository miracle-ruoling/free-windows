# Does the visible Start panel live inside StartMenuExperienceHost's full-screen window?
# Open Start, move THAT window, diff the screenshots.
param([int]$Dx = 150, [int]$Dy = 120, [switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WY2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Info {
    public IntPtr H; public string Cls=""; public string Txt=""; public uint Pid; public bool Vis; public RECT R; public int Style;
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
  public static List<Info> Kids(IntPtr p) {
    List<Info> l = new List<Info>();
    EnumChildWindows(p, delegate(IntPtr h, IntPtr lp) { l.Add(One(h)); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WY2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WY2]::GetSystemMetrics(0)), ([WY2]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WY2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WY2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$smeh = @((Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue).Id)
$sh = @((Get-Process SearchHost -ErrorAction SilentlyContinue).Id)
Write-Output ("SMEH=" + ($smeh -join ',') + " SearchHost=" + ($sh -join ','))
Esc; Start-Sleep -Milliseconds 600
[WY2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WY2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WY2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WY2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300
$all = [WY2]::All()
Write-Output "--- every enumerated window of SMEH / SearchHost (no width filter) ---"
foreach ($w in $all) {
    if (($smeh -contains [int]$w.Pid) -or ($sh -contains [int]$w.Pid)) { Write-Output ("  " + $w.Show()) }
}
$target = $all | Where-Object { ($smeh -contains [int]$_.Pid) -and (($_.R.Right - $_.R.Left) -gt 500) } |
          Sort-Object { - (($_.R.Right - $_.R.Left) * ($_.R.Bottom - $_.R.Top)) } | Select-Object -First 1
if (-not $target) { Write-Output "no big SMEH window enumerated"; Esc; exit }
Write-Output ("TARGET " + $target.Show())
foreach ($c in [WY2]::Kids($target.H)) { Write-Output ("  child " + $c.Show()) }
Shot "smeh_a.png"
$ok = [WY2]::SetWindowPos($target.H, [IntPtr]::Zero, $target.R.Left + $Dx, $target.R.Top + $Dy, 0, 0,
                          0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 500
$now = ([WY2]::All() | Where-Object { $_.H -eq $target.H } | Select-Object -First 1)
Write-Output ("moved ok=$ok -> " + $(if ($now) { $now.Show() } else { "not enumerated now" }))
Shot "smeh_b.png"
[void][WY2]::SetWindowPos($target.H, [IntPtr]::Zero, $target.R.Left, $target.R.Top, 0, 0,
                          0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 400
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 400 }
