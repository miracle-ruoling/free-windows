. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class S2 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static int Top() { IntPtr h = FindWindow("DockStripWindow", "dock"); RC r; GetWindowRect(h, out r); return r.T; }
}
"@
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 1000
Write-Output ("strip y=" + [S2]::Top())
$n0 = (Get-LogLines).Count
Start-Sleep -Milliseconds 100
[void][S]::SetCursorPos(800, 76); Start-Sleep -Milliseconds 300
[S]::LeftClick(); Start-Sleep -Milliseconds 700
$lines = @(Get-LogLines)
$lines[$n0..($lines.Count-1)] | Where-Object { $_ -ne '' -and $_ -match 'press: hook|LBUTTONDOWN|press audit|click slot' } | ForEach-Object { $_ }
