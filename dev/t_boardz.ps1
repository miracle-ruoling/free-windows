. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class NZ {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint f);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr ByClass(string cls, bool visibleOnly, int minW) {
    IntPtr f = IntPtr.Zero;
    EnumWindows((h, l) => {
      var c = new StringBuilder(128); GetClassName(h, c, 128);
      if (c.ToString() != cls) return true;
      if (visibleOnly && !IsWindowVisible(h)) return true;
      RC r; GetWindowRect(h, out r);
      if (r.R - r.L < minW) return true;
      f = h; return false;
    }, IntPtr.Zero);
    return f;
  }
  public static string Info(IntPtr h) {
    if (h == IntPtr.Zero) return "none";
    RC r; GetWindowRect(h, out r);
    int ex = GetWindowLong(h, -20);
    return string.Format("{0} {1},{2} {3}x{4} vis={5} topmost={6}", h, r.L, r.T, r.R-r.L, r.B-r.T, IsWindowVisible(h), (ex & 0x8) != 0);
  }
  public static IntPtr At(int x, int y) { return WindowFromPoint(new POINT{X=x, Y=y}); }
  public static void Top(IntPtr h) { SetWindowPos(h, (IntPtr)(-1), 0,0,0,0, 0x0001|0x0002|0x0010); }
  public static void NoTop(IntPtr h) { SetWindowPos(h, (IntPtr)(-2), 0,0,0,0, 0x0001|0x0002|0x0010); }
}
"@
$strip = [NZ]::ByClass('DockStripWindow', $false, 50)
$board = [NZ]::ByClass('DockGroupBoxWindow', $true, 50)
Write-Output ("strip: " + [NZ]::Info($strip))
Write-Output ("board: " + [NZ]::Info($board))
$r = New-Object S+RECT; [void][S]::GetWindowRect($strip, [ref]$r)
$cx = $r.Left + 22 + 3 * 78 + 36; $cy = $r.Top + 48
Write-Output ("icon centre -> " + [NZ]::Info([NZ]::At($cx, $cy)))
if ($board -ne [IntPtr]::Zero) {
  [NZ]::NoTop($strip); [NZ]::Top($board)
  Start-Sleep -Milliseconds 120
  Write-Output ("simulated (strip non-topmost, board topmost) -> " + [NZ]::Info([NZ]::At($cx, $cy)))
  Start-Sleep -Milliseconds 500
  Write-Output ("after invariant -> " + [NZ]::Info([NZ]::At($cx, $cy)))
  Write-Output ("strip now: " + [NZ]::Info($strip))
  Write-Output ("board now: " + [NZ]::Info($board))
}
(Get-LogLines | Where-Object { $_ -match 'zorder:' } | Select-Object -Last 4) -join "`n"
