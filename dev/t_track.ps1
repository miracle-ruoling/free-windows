. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class W4 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static IntPtr H(string cls, string title) { return FindWindow(cls, title); }
  public static string R(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    RC r; GetWindowRect(h, out r);
    return r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T);
  }
  public static void MoveBy(IntPtr h, int dx, int dy) {
    RC r; GetWindowRect(h, out r);
    SetWindowPos(h, IntPtr.Zero, r.L + dx, r.T + dy, 0, 0, 0x0001 | 0x0004 | 0x0010); // NOSIZE|NOZORDER|NOACTIVATE
  }
}
"@
$strip = [W4]::H("DockStripWindow", "dock")
$tray = [W4]::H("DockTrayBarWindow", "dock tray bar")
function Pose([string]$tag) {
  Write-Output ("{0,-22} strip={1,-20} tray={2,-20}" -f $tag, [W4]::R($strip), [W4]::R($tray))
}
[void][S]::SetCursorPos(700, 600); Start-Sleep -Milliseconds 1300
Pose 'hidden'
$before = (Get-LogLines).Count
[W4]::MoveBy($strip, 0, 143); Start-Sleep -Milliseconds 600
Pose 'strip shoved +143'
(Get-LogLines | Select-Object -Skip $before | Where-Object { $_ -match 'slide track' }) -join "`n"
[W4]::MoveBy($tray, 0, -143); Start-Sleep -Milliseconds 600
Pose 'tray shoved -143'
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 1300
Pose 'after wake'
