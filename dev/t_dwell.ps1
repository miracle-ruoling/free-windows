. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class T2 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static int Top() { IntPtr h = FindWindow("DockStripWindow", "dock"); RC r; GetWindowRect(h, out r); return r.T; }
}
"@
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 700          # wake
$wakeAt = (Get-LogLines | Select-String 'hide: group 1 wake' | Select-Object -Last 1).Line.Substring(0,12)
Write-Output ("wake at " + $wakeAt + " strip y=" + [T2]::Top())
[void][S]::SetCursorPos(700, 600)                                        # leave immediately
$t0 = Get-Date
while (((Get-Date) - $t0).TotalMilliseconds -lt 2600) {
  Start-Sleep -Milliseconds 120
}
$hideLine = (Get-LogLines | Select-String 'hide: group 1 hide' | Select-Object -Last 1).Line
Write-Output ("next hide line: " + $hideLine)
Write-Output ("strip y now " + [T2]::Top())
