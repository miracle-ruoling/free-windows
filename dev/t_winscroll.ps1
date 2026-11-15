# Scroll the strip and prove the Windows button stays in place while the icons move.
param([int]$Notches = 3)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WV {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Strip() {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == "DockStripWindow") { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
}
"@
[void][WV]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WV]::GetSystemMetrics(0)), ([WV]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
$h = [WV]::Strip()
if ($h -eq [IntPtr]::Zero) { Write-Output "no strip"; exit 1 }
$r = New-Object WV+RECT
[void][WV]::GetWindowRect($h, [ref]$r)
Write-Output ("strip " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
$delta = -120 * $Notches
$wp = [IntPtr]([int64]($delta -shl 16 -band 0xFFFF0000))
$lp = [IntPtr]([int64](($r.Top + 60) -shl 16) -bor ($r.Left + 300))
Write-Output ("posting WM_MOUSEWHEEL delta=" + $delta)
[void][WV]::PostMessage($h, 0x020A, $wp, $lp)
Start-Sleep -Milliseconds 500
Shot "scroll_after.png"
