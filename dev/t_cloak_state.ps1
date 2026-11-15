# Which window's uncloak opens the Start menu on this build? Query DWM cloak state for
# the candidate hosts (the shell-flyout-positions mod keys off DWMWA_CLOAK=0 on these).
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WB2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public const int DWMWA_CLOAKED = 14;
  public static string One(IntPtr h) {
    uint p; GetWindowThreadProcessId(h, out p);
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
    RECT r; GetWindowRect(h, out r);
    int cloaked = -1;
    DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, sizeof(int));
    return string.Format("h={0} pid={1} cls={2} txt='{3}' vis={4} cloaked={5} rect={6},{7} {8}x{9}",
      h.ToInt64(), p, b, t, IsWindowVisible(h), cloaked, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top);
  }
  public static IntPtr Root(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    return GetAncestor(WindowFromPoint(p), 2);
  }
}
"@
[void][WB2]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Esc {
    [WB2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WB2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$sh = @((Get-Process SearchHost -ErrorAction SilentlyContinue).Id)
$smeh = @((Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue).Id)
Write-Output ("SearchHost pid=" + ($sh -join ',') + " SMEH pid=" + ($smeh -join ','))
Esc; Start-Sleep -Milliseconds 700
Write-Output "--- Start closed: probe points ---"
foreach ($pt in @(@(600,300), @(900,500))) {
    $h = [WB2]::Root($pt[0], $pt[1])
    Write-Output ("  " + $pt[0] + "," + $pt[1] + " -> " + [WB2]::One($h))
}
[WB2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WB2]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WB2]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
[WB2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1300
Write-Output "--- Start open: probe points (who owns the panel's pixels) ---"
foreach ($pt in @(@(500,200), @(600,300), @(900,500), @(1200,900))) {
    $h = [WB2]::Root($pt[0], $pt[1])
    Write-Output ("  " + $pt[0] + "," + $pt[1] + " -> " + [WB2]::One($h))
}
Write-Output "--- known candidates ---"
if ($sh.Count) { Write-Output ("  SearchHost core: " + [WB2]::One([IntPtr]66272)) }
if ($smeh.Count) { Write-Output ("  SMEH core:       " + [WB2]::One([IntPtr]131590)) }
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 400 }
