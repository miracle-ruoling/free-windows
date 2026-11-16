# R2 probe: is the group frame there, is it where the members say, and does it let clicks
# through? (A layered window is hit-tested through its alpha, so "pass-through" is a property
# of the pixels - WindowFromPoint inside the frame must never come back as the frame.)
#
#   .\t_groupbox.ps1                 # expected margin 8
#   .\t_groupbox.ps1 -Margin 12
param([int]$Margin = 8, [int]$SettleMs = 500)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class GB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Find(string cls) {
    // Several DockGroupBoxWindow exist since G2 (one per group, created up front and hidden):
    // always prefer the visible one.
    IntPtr first = IntPtr.Zero, visible = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
      if (b.ToString() != cls) return true;
      if (first == IntPtr.Zero) first = h;
      if (Show(h)) { visible = h; return false; }
      return true; }, IntPtr.Zero);
    return visible != IntPtr.Zero ? visible : first;
  }
  static bool Show(IntPtr h) { return IsWindowVisibleNative(h); }
  [DllImport("user32.dll", EntryPoint = "IsWindowVisible")] static extern bool IsWindowVisibleNative(IntPtr h);
  public static string Name(IntPtr h) {
    if (h == IntPtr.Zero) return "(desktop)";
    StringBuilder b = new StringBuilder(160); GetClassName(h, b, 160);
    return b.ToString();
  }
  public static string At(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    return x + "," + y + " -> " + Name(WindowFromPoint(p));
  }
}
"@
[void][GB]::SetProcessDpiAwarenessContext([IntPtr](-4))
$strip = [GB]::Find('DockStripWindow')
$bar   = [GB]::Find('DockTrayBarWindow')
$box   = [GB]::Find('DockGroupBoxWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no strip'; exit 1 }
if ($box -eq [IntPtr]::Zero) { Write-Output 'no frame window (nothing to frame, or R2 not deployed)'; exit 1 }

$sr = New-Object GB+RECT; [void][GB]::GetWindowRect($strip, [ref]$sr)
$br = New-Object GB+RECT; [void][GB]::GetWindowRect($bar, [ref]$br)
$wantL = [Math]::Min($sr.Left, $br.Left) - $Margin
$wantT = [Math]::Min($sr.Top, $br.Top) - $Margin
$wantR = [Math]::Max($sr.Right, $br.Right) + $Margin
$wantB = [Math]::Max($sr.Bottom, $br.Bottom) + $Margin
Write-Output ("strip {0},{1}-{2},{3}  companion {4},{5}-{6},{7}" -f $sr.Left,$sr.Top,$sr.Right,$sr.Bottom,$br.Left,$br.Top,$br.Right,$br.Bottom)
Write-Output ("expected frame {0},{1}-{2},{3} (margin {4})" -f $wantL,$wantT,$wantR,$wantB,$Margin)

function Show-Box($label) {
  # G2: there are kMaxGroups windows of this class and they are all hidden until the group is
  # up - so re-pick the visible one every time instead of caching the handle found at startup.
  $box = [GB]::Find('DockGroupBoxWindow')
  $r = New-Object GB+RECT; [void][GB]::GetWindowRect($box, [ref]$r)
  $cp = New-Object GB+POINT; [void][GB]::GetCursorPos([ref]$cp)
  Write-Output ("[{0}] cursor {1},{2} | frame visible={3} rect={4},{5}-{6},{7} size={8}x{9} | companion visible={10}" -f `
    $label, $cp.X, $cp.Y, [GB]::IsWindowVisible($box), $r.Left, $r.Top, $r.Right, $r.Bottom,
    ($r.Right-$r.Left), ($r.Bottom-$r.Top), [GB]::IsWindowVisible($bar))
  if ([GB]::IsWindowVisible($box)) {
    $ok = ($r.Left -eq $wantL -and $r.Top -eq $wantT -and $r.Right -eq $wantR -and $r.Bottom -eq $wantB)
    Write-Output ("  geometry matches the members + margin {0}: {1}" -f $Margin, $ok)
    # inside the frame: must pass through; on the 1 px line: that is the frame itself
    $inside = @(
      [int](($r.Left+$r.Right)/2), [int](($r.Top+$r.Bottom)/2),
      ($r.Left + 30), ($r.Top + 30)
    )
    foreach ($i in 0..1) { Write-Output ("  " + [GB]::At($inside[$i*2], $inside[$i*2+1])) }
    Write-Output ("  " + [GB]::At($r.Left, [int](($r.Top+$r.Bottom)/2)))
  }
}

# 1) pointer on the strip -> frame shows
$c = @([int](($sr.Left+$sr.Right)/2), [int](($sr.Top+$sr.Bottom)/2))
[void][GB]::SetCursorPos($c[0], $c[1]); Start-Sleep -Milliseconds $SettleMs
Show-Box 'pointer on strip'

# 2) pointer in the empty part of the frame (below the strip, left of the companion) -> stays
$mx = $sr.Left + 20
$my = [Math]::Min($wantB - 6, $br.Bottom + 2)
[void][GB]::SetCursorPos($mx, $my); Start-Sleep -Milliseconds $SettleMs
Show-Box 'pointer inside the frame, not on a window'

# 3) pointer far away -> frame goes away
[void][GB]::SetCursorPos(60, 900); Start-Sleep -Milliseconds ($SettleMs + 300)
Show-Box 'pointer far away'

# 4) back on the strip, then 25 px outside the frame (past the 6 px hysteresis) -> goes away
[void][GB]::SetCursorPos($c[0], $c[1]); Start-Sleep -Milliseconds $SettleMs
[void][GB]::SetCursorPos(($wantL - 25), [int](($wantT+$wantB)/2)); Start-Sleep -Milliseconds ($SettleMs + 300)
Show-Box 'pointer 25 px outside the frame'
