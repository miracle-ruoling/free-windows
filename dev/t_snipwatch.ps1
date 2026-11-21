# Task 1, second half: what does the Win+Shift+S overlay look like to us?
# Opens Snipping Tool's snip overlay ("SnippingTool.exe /clip"), dumps the z-order while it is up,
# then closes it again. Nothing is captured and nothing is clicked.
#
#   .\t_snipwatch.ps1
param([int]$WaitMs = 1600)
$ErrorActionPreference = 'Continue'
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class SN {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static string Top(int n) {
    var sb = new StringBuilder();
    int idx = 0;
    IntPtr fg = GetForegroundWindow();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      var b = new StringBuilder(200); GetClassName(h, b, 200);
      var t = new StringBuilder(200); GetWindowText(h, t, 120);
      RECT r; GetWindowRect(h, out r);
      int ck; bool cloak = DwmGetWindowAttribute(h, 14, out ck, 4) == 0 && ck != 0;
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool top = ((long)GetWindowLong(h, -20) & 0x8L) != 0;
      sb.Append(string.Format("  z#{0,-3} {1} {2,-44} pid={3,-6} tm={4} cloak={5} {6},{7} {8}x{9} {10}{11}\n",
        idx, h == fg ? "FG" : "  ", b.ToString(), pid, top ? 1 : 0, cloak ? 1 : 0,
        r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top,
        t.ToString(), h == fg ? "  <== foreground" : ""));
      idx++;
      return idx < n;
    }, IntPtr.Zero);
    return sb.ToString();
  }
}
"@
[void][SN]::SetProcessDpiAwarenessContext([IntPtr](-4))

Write-Output "== before =="
Write-Output ([SN]::Top(18))

$snip = Get-Command SnippingTool.exe -ErrorAction SilentlyContinue
if (-not $snip) { $snip = Get-Command "$env:SystemRoot\System32\SnippingTool.exe" -ErrorAction SilentlyContinue }
Write-Output ("SnippingTool: " + ($snip.Source | Out-String).Trim())
$p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\SnippingTool.exe') -ArgumentList '/clip' -PassThru
Start-Sleep -Milliseconds $WaitMs
Write-Output ""
Write-Output ("== with the snip overlay up (after $WaitMs ms, pid=" + $p.Id + ") ==")
Write-Output ([SN]::Top(18))

# get out of the snip: Escape first (Snipping Tool accepts it), kill as the fallback
Add-Type -AssemblyName System.Windows.Forms
try { [System.Windows.Forms.SendKeys]::SendWait("{ESC}") } catch {}
Start-Sleep -Milliseconds 400
if (-not $p.HasExited) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Output "(overlay process killed)" } catch { Write-Output "(could not kill the overlay process)" }
}
Start-Sleep -Milliseconds 500
Write-Output ""
Write-Output "== after =="
Write-Output ([SN]::Top(14))
