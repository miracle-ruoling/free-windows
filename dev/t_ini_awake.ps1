. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class P {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static IntPtr H(string c, string t) { return FindWindow(c, t); }
  public static int Top(IntPtr h) { RC r; GetWindowRect(h, out r); return r.T; }
  public static void Press(IntPtr h, int x, int y) {
    IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
    SendMessage(h, 0x0201, (IntPtr)1, lp); System.Threading.Thread.Sleep(60);
    SendMessage(h, 0x0202, (IntPtr)0, lp);
  }
}
"@
$strip = [P]::H("DockStripWindow", "dock")
$tray = [P]::H("DockTrayBarWindow", "dock tray bar")
$ini = "$env:LOCALAPPDATA\Programs\Dock\dock.ini"
function IniY([string]$sec) {
  $lines = Get-Content $ini; $cur = ''; foreach ($l in $lines) { if ($l -match '^\[(.+)\]') { $cur = $Matches[1] }; if ($cur -eq $sec -and $l -match '^y=(-?\d+)') { return [int]$Matches[1] } }; return 99999
}
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 1000
Write-Output ("awake: strip=" + [P]::Top($strip) + " tray=" + [P]::Top($tray))
[void][S]::SetCursorPos(700, 600); Start-Sleep -Milliseconds 1400
Write-Output ("hidden: strip=" + [P]::Top($strip) + " tray=" + [P]::Top($tray) + "  ini tray y=" + (IniY 'traybar') + " dock y=" + (IniY 'dock'))
[P]::Press($tray, 2, 40)          # press the invisible tray's edge -> that path saves its geometry
Start-Sleep -Milliseconds 700
Write-Output ("after edge press on the parked tray: ini tray y=" + (IniY 'traybar') + " dock y=" + (IniY 'dock'))
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 1200
Write-Output ("woke: strip=" + [P]::Top($strip) + " tray=" + [P]::Top($tray) + "  ini tray y=" + (IniY 'traybar'))
