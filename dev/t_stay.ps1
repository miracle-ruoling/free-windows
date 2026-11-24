. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class ST {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static int Top(string cls, string title) { IntPtr h = FindWindow(cls, title); if (h == IntPtr.Zero) return -99999; RC r; GetWindowRect(h, out r); return r.T; }
}
"@
function Top() { [ST]::Top("DockStripWindow", "dock") }
Write-Output ("start strip y=" + (Top))
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 1000
Write-Output ("after band hover y=" + (Top))
[void][S]::SetCursorPos(800, 60); Start-Sleep -Milliseconds 500
Write-Output ("cursor on the row y=" + (Top))
for ($i = 0; $i -lt 8; $i++) { Start-Sleep -Milliseconds 500; Write-Output ("  +{0} ms y={1}" -f (($i+1)*500), (Top)) }
$before = (Get-LogLines).Count
Start-Sleep -Milliseconds 200
(Get-LogLines | Select-Object -Last 12 | Where-Object { $_ -match 'hide: group 1 (hide|wake)|target -> |hover ->' }) -join "`n"
