. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class W2 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static string Get(string cls, string title) {
    IntPtr h = FindWindow(cls, title);
    if (h == IntPtr.Zero) return "none";
    RC r; GetWindowRect(h, out r);
    return r.L + "," + r.T + " " + (r.R - r.L) + "x" + (r.B - r.T);
  }
}
"@
function Shot([string]$tag) {
  $s = [W2]::Get("DockStripWindow", "dock")
  $t = [W2]::Get("DockTrayBarWindow", "dock tray bar")
  $b = [W2]::Get("DockGroupBoxWindow", "dock group")
  $sw = New-Object System.Diagnostics.Stopwatch
  $sw.Start()
  $p = New-Object S+POINT; [void][S]::GetCursorPos([ref]$p)
  Write-Output ("{0,-8} strip={1,-22} tray={2,-22} box={3,-22} cursor={4},{5}" -f $tag, $s, $t, $b, $p.X, $p.Y)
}
$p = New-Object S+POINT
[void][S]::SetCursorPos(700, 600)     # away from the group -> it hides
for ($i = 0; $i -lt 8; $i++) { Shot ("hide" + $i); Start-Sleep -Milliseconds 120 }
Start-Sleep -Milliseconds 800
Shot 'hidden'
[void][S]::SetCursorPos(800, 2)        # wake
for ($i = 0; $i -lt 8; $i++) { Shot ("wake" + $i); Start-Sleep -Milliseconds 120 }
Start-Sleep -Milliseconds 800
Shot 'awake'
