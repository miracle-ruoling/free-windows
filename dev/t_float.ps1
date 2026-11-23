<#
  Float windows: where they are, how they stack, and what they look like.

  -Dump     list every window of ours (class, title, rect, visible, ex-style) plus the z index of
            each float window against Progman (the desktop).
  -Shot N   PrintWindow the float window with id N into dev\float_<N>.png (works for a layered
            window that sits *behind* every app window, which a screen grab cannot show).

  The probe is DPI aware on purpose: without SetProcessDpiAwarenessContext the rectangles come
  back scaled by the display's DPI factor (the §1.5 trap in NEXT_TASKS.md).
#>
param([switch]$Quiet, [int]$Shot = -1, [string]$Out)

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public class FW {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
  public struct RECT { public int L, T, R, B; }

  public static string Cls(IntPtr h) { var sb = new StringBuilder(128); GetClassName(h, sb, 128); return sb.ToString(); }
  public static string Title(IntPtr h) { var sb = new StringBuilder(256); GetWindowText(h, sb, 256); return sb.ToString(); }

  // Every top-level window in z order, top-most first (EnumWindows order).
  public static System.Collections.Generic.List<IntPtr> All() {
    var list = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h, l) => { list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }
  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { if (Cls(h) == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
}
"@

[void][FW]::SetProcessDpiAwarenessContext([IntPtr](-4))     # per-monitor v2

$all = [FW]::All()
$progman = [FW]::ByClass("Progman")
$progIndex = if ($progman -ne [IntPtr]::Zero) { $all.IndexOf($progman) } else { -1 }
"z order: index 0 = topmost window; Progman (the desktop) is at index $progIndex"
""

if (-not $Quiet) {
  $i = 0
  foreach ($h in $all) {
    $c = [FW]::Cls($h)
    if ($c -notlike "Dock*") { $i++; continue }
    $t = [FW]::Title($h)
    $r = New-Object FW+RECT
    [void][FW]::GetWindowRect($h, [ref]$r)
    $vis = [FW]::IsWindowVisible($h)
    $ex = [FW]::GetWindowLongPtr($h, -20).ToInt64()
    $topmost = ($ex -band 0x8) -ne 0
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    "z#{0,-4} {1,-22} '{2}' vis={3} topmost={4} {5},{6} {7}x{8}" -f $i, $c, $t, $vis, $topmost, $r.L, $r.T, $w, $hh
    $i++
  }
}

if ($Shot -ge 0) {
  $target = [IntPtr]::Zero
  foreach ($h in $all) {
    if ([FW]::Cls($h) -eq "DockFloatWindow" -and [FW]::Title($h) -eq "dock float $Shot") { $target = $h; break }
  }
  if ($target -eq [IntPtr]::Zero) { "no 'dock float $Shot' window"; exit 1 }
  $r = New-Object FW+RECT
  [void][FW]::GetWindowRect($target, [ref]$r)
  $w = $r.R - $r.L; $hh = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $hh, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [FW]::PrintWindow($target, $hdc, 2)      # PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  # PrintWindow of a *layered* window can come back empty; fall back to a screen grab of the rect,
  # which only works while the desktop (not an app window) is what is behind it.
  $blank = $true
  for ($y = 0; $y -lt $hh -and $blank; $y += 3) {
    for ($x = 0; $x -lt $w -and $blank; $x += 3) {
      if ($bmp.GetPixel($x, $y).ToArgb() -ne 0) { $blank = $false }
    }
  }
  if ($blank) {
    $g2 = [System.Drawing.Graphics]::FromImage($bmp)
    $g2.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $hh))
    $g2.Dispose()
  }
  $g.Dispose()
  if (-not $Out) { $Out = Join-Path $PSScriptRoot "float_$Shot.png" }
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "saved $Out ($w x $hh, printwindow=$ok blank=$blank)"
}
