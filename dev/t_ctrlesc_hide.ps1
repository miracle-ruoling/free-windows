# Open Start with Ctrl+Esc, then put the taskbar back down: does Start survive?
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WR {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Bar { public IntPtr H; public string Cls=""; public RECT R; }
  public static List<Bar> Bars() {
    List<Bar> l = new List<Bar>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      string c = b.ToString();
      if (c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") {
        Bar x = new Bar(); x.H = h; x.Cls = c; RECT r; GetWindowRect(h, out r); x.R = r;
        l.Add(x);
      }
      return true; }, IntPtr.Zero);
    return l;
  }
  public static string Fg() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
    RECT r; GetWindowRect(h, out r);
    uint p; GetWindowThreadProcessId(h, out p);
    return string.Format("{0} cls={1} txt='{2}' pid={3} rect={4},{5} {6}x{7}", h.ToInt64(), b, t, p, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top);
  }
}
"@
[void][WR]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WR]::GetSystemMetrics(0)), ([WR]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Esc {
    [WR]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WR]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
function Show([string]$tag) {
    Write-Output ("--- " + $tag + " --- fg=" + [WR]::Fg())
    foreach ($b in [WR]::Bars()) {
        Write-Output ("  " + $b.Cls + " " + $b.H + " rect=" + $b.R.Left + "," + $b.R.Top + " " + ($b.R.Right-$b.R.Left) + "x" + ($b.R.Bottom-$b.R.Top))
    }
}
Esc; Start-Sleep -Milliseconds 400
Show "before"
[WR]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WR]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
Show "start open (+0.9s)"
Shot "ctrlesc_hide_a.png"
Start-Sleep -Milliseconds 600
Show "start open (+1.5s)"
foreach ($b in [WR]::Bars()) { [void][WR]::PostMessage($b.H, 0x0113, [IntPtr]2, [IntPtr]::Zero) }
Write-Output "posted hide to the taskbar"
Start-Sleep -Milliseconds 700
Show "after hiding the taskbar (+0.7s)"
Shot "ctrlesc_hide_b.png"
Start-Sleep -Milliseconds 600
Show "after hiding the taskbar (+1.3s)"
Shot "ctrlesc_hide_c.png"
Esc; Start-Sleep -Milliseconds 400
Show "after esc"
