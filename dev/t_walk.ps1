# Walk a dock window back to a given position the way the user would: grab it and drag it.
# (An external SetWindowPos would be undone by the dock's own g_cfg on the next save/restart,
# so the drag path is the honest one - it also exercises the same code the user uses.)
#
#   .\t_walk.ps1 -Class DockStripWindow -X 842 -Y 184
#   .\t_walk.ps1 -Class DockTrayBarWindow -X 1369 -Y 270
param(
    [Parameter(Mandatory = $true)] [string]$Class,
    [Parameter(Mandatory = $true)] [int]$X,
    [Parameter(Mandatory = $true)] [int]$Y,
    [int]$GrabX = -1, [int]$GrabY = -1
)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public class Walk {
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static int[] Centre(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    return new int[] { (r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2 };
  }
  public static string WalkTo(IntPtr h, int tx, int ty, int grabX, int grabY, bool offsetAtThreshold) {
    RECT r0; GetWindowRect(h, out r0);
    int gx = r0.Left + grabX, gy = r0.Top + grabY;
    SetCursorPos(gx, gy); Thread.Sleep(450);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(60);
    SetCursorPos(gx + 6, gy + 6); Thread.Sleep(60);      // past the 4 px drag threshold
    // Where the grab offset is recorded decides the mapping, and the two windows differ:
    //   * the strip records it on WM_LBUTTONDOWN  -> the 6 px threshold step moves it too;
    //   * the tray bar records it when the drag actually starts (after that step) -> it does not.
    // Measured both ways; getting this wrong lands the window exactly 6 px off.
    int bias = offsetAtThreshold ? 6 : 0;
    int cx0 = gx + bias + (tx - r0.Left), cy0 = gy + bias + (ty - r0.Top);
    for (int i = 1; i <= 20; i++) {
      SetCursorPos(gx + 6 + (int)((long)(cx0 - gx - 6) * i / 20),
                   gy + 6 + (int)((long)(cy0 - gy - 6) * i / 20));
      Thread.Sleep(18);
    }
    Thread.Sleep(150);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(300);
    RECT e; GetWindowRect(h, out e);
    return "from " + r0.Left + "," + r0.Top + " to " + e.Left + "," + e.Top +
           " (wanted " + tx + "," + ty + ")";
  }
}
"@
[void][Walk]::SetProcessDpiAwarenessContext([IntPtr](-4))
$h = [Walk]::Find($Class)
if ($h -eq [IntPtr]::Zero) { Write-Output "no $Class"; exit 1 }
if ($GrabX -lt 0) {
    # default grab points: the chevron on the strip (transparent mode only hit-tests glyphs),
    # the first cell for the tray bar
    if ($Class -eq 'DockStripWindow') {
        $log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
        $line = (Select-String -Path $log -Pattern 'layout:' | Select-Object -Last 1).Line
        $m = [regex]::Match($line, 'chevron=(\d+),(\d+)-(\d+),(\d+)')
        $GrabX = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
        $GrabY = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
    } else {
        $GrabX = 46; $GrabY = 30
    }
}
if ($Class -eq 'DockTrayBarWindow') {
    # the companion is only on screen while the pointer is on the strip: warm it up first,
    # otherwise the press lands on whatever is behind the (hidden) layered window
    $s = [Walk]::Find('DockStripWindow')
    if ($s -ne [IntPtr]::Zero) {
        $centre = [Walk]::Centre($s)
        [void][Walk]::SetCursorPos($centre[0], $centre[1])
        Start-Sleep -Milliseconds 450
    }
}
Write-Output ([Walk]::WalkTo($h, $X, $Y, $GrabX, $GrabY, ($Class -eq 'DockTrayBarWindow')))
