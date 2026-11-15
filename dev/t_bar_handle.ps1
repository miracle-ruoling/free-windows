# Remember the taskbar handle while it is hidden, then press Win (taskbar up) and post
# the hide timer to that remembered handle. Does the taskbar go back down? Does Start stay?
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WT {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static List<IntPtr> Bars() {
    List<IntPtr> l = new List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      string c = b.ToString();
      if (c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") l.Add(h);
      return true; }, IntPtr.Zero);
    return l;
  }
}
"@
[void][WT]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WT]::GetSystemMetrics(0)), ([WT]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Info([IntPtr]$h, [string]$tag) {
    $r = New-Object WT+RECT
    $ok = [WT]::GetWindowRect($h, [ref]$r)
    Write-Output ("  [$tag] h=" + $h.ToInt64() + " alive=" + [WT]::IsWindow($h) + " vis=" + [WT]::IsWindowVisible($h) + " rect=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top) + " (GetWindowRect=" + $ok + ")")
}
function Esc {
    [WT]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WT]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
Esc; Start-Sleep -Milliseconds 500
$bars = [WT]::Bars()
Write-Output ("bars seen while hidden: " + (($bars | ForEach-Object { $_.ToInt64() }) -join ','))
if ($bars.Count -eq 0) { Write-Output "nothing to remember, abort"; exit }
$bar = $bars[0]
Info $bar "hidden"
[WT]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80
[WT]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 900
$n = [WT]::Bars().Count
Info $bar ("after win (enumerated bars: " + $n + ")")
Shot "bar_handle_a.png"
$ok = [WT]::PostMessage($bar, 0x0113, [IntPtr]2, [IntPtr]::Zero)
Write-Output ("posted WM_TIMER(2) to the remembered handle ok=" + $ok)
Start-Sleep -Milliseconds 800
Info $bar "after hide post"
Shot "bar_handle_b.png"
Start-Sleep -Milliseconds 800
Info $bar "after hide post +0.8s"
Shot "bar_handle_c.png"
