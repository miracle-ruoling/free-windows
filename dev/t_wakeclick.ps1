. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class T3 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static int Top() { IntPtr h = FindWindow("DockStripWindow", "dock"); RC r; GetWindowRect(h, out r); return r.T; }
}
"@
# hide the group, then click where the bar lives -> it must come out
[void][S]::SetCursorPos(700, 600); Start-Sleep -Milliseconds 1500
Write-Output ("hidden: strip y=" + [T3]::Top())
$before = (Get-LogLines).Count
[void][S]::SetCursorPos(800, 60); Start-Sleep -Milliseconds 250
[S]::LeftClick(); Start-Sleep -Milliseconds 800
Write-Output ("after clicking the bar's area: strip y=" + [T3]::Top())
(Get-LogLines | Select-Object -Skip $before | Where-Object { $_ -ne '' -and $_ -match 'press:|hide: group 1 wake|LBUTTONDOWN' }) -join "`n"
Start-Sleep -Milliseconds 1500
Write-Output ("2.5 s later: strip y=" + [T3]::Top())
