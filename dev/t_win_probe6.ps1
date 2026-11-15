# Recon 6: does moving the foreground window move the visible Start panel?
#   -Layer  : move the full-screen StartMenuExperienceHost window instead
param([switch]$Layer, [int]$Dx = -260, [int]$Dy = 160)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WE {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static RECT Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
  public static IntPtr FindByPid(uint pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid) return true;
      RECT r; GetWindowRect(h, out r);
      if (r.Right - r.Left < 100) return true;
      found = h; return false; }, IntPtr.Zero);
    return found;
  }
}
"@
[void][WE]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$name) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap ([WE]::GetSystemMetrics(0)), ([WE]::GetSystemMetrics(1))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $PSScriptRoot $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
$fg0 = [WE]::GetForegroundWindow()
Write-Output ("fg before=" + $fg0 + " rect=" + [WE]::Rect($fg0).Left + "," + [WE]::Rect($fg0).Top)
[WE]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70
[WE]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1000
$fg = [WE]::GetForegroundWindow()
$target = $fg
if ($Layer) {
    $smeh = [WE]::FindByPid((Get-Process StartMenuExperienceHost).Id)
    Write-Output ("layer mode: using SMEH window " + $smeh)
    if ($smeh -ne [IntPtr]::Zero) { $target = $smeh }
}
$r0 = [WE]::Rect($target)
Write-Output ("target=" + $target + " fg=" + $fg + " rect=" + $r0.Left + "," + $r0.Top + " " + ($r0.Right-$r0.Left) + "x" + ($r0.Bottom-$r0.Top))
Shot "w6_a.png"
$ok = [WE]::SetWindowPos($target, [IntPtr]::Zero, $r0.Left + $Dx, $r0.Top + $Dy, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 500
$r1 = [WE]::Rect($target)
Write-Output ("moved ok=$ok -> " + $r1.Left + "," + $r1.Top)
Shot "w6_b.png"
[void][WE]::SetWindowPos($target, [IntPtr]::Zero, $r0.Left, $r0.Top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010 -bor 0x0400)
Start-Sleep -Milliseconds 400
Write-Output ("restored -> " + [WE]::Rect($target).Left + "," + [WE]::Rect($target).Top)
[WE]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
[WE]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 500
Write-Output "done"
