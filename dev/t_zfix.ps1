# Task 1 acceptance probe: does the dock's z-order watchdog repair the two failure cases
# without anybody calling SetWindowPos from outside?
#
#   .\t_zfix.ps1            # form appears above the dock, then we only watch
#
# A: a later topmost window covers the strip          -> watchdog must climb back on top (<= ~1 s)
# B: the strip loses WS_EX_TOPMOST                     -> watchdog must promote it again
# C: a capture overlay comes to the front              -> the dock must step *below* it
#    and go back to topmost once it is gone            (needs Snipping Tool; -SkipCapture skips)
param([switch]$SkipCapture, [int]$Settle = 1400)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ZF {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static readonly IntPtr TOPMOST = new IntPtr(-1), NOTOPMOST = new IntPtr(-2);
  public const uint NOMOVE = 2, NOSIZE = 1, NOACTIVATE = 0x10;

  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  // z index of `want` and whether it still carries WS_EX_TOPMOST
  public static string Where(IntPtr want) {
    int idx = 0;
    for (IntPtr h = GetWindowTop(); h != IntPtr.Zero; h = Next(h), idx++) {
      if (h != want) continue;
      RECT r; GetWindowRect(want, out r);
      bool top = ((long)GetWindowLong(want, -20) & 0x8L) != 0;
      return "z#" + idx + " topmost=" + (top ? 1 : 0) + " vis=" + (IsWindowVisible(want) ? 1 : 0) +
             " " + r.Left + "," + r.Top + "-" + r.Right + "," + r.Bottom;
    }
    return "(not in z-order)";
  }
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  public static IntPtr GetWindowTop() { return GetTopWindow(IntPtr.Zero); }
  public static IntPtr Next(IntPtr h) { return GetWindow(h, 2); }

  // is `other` above `want` and overlapping it?
  public static bool Above(IntPtr want, IntPtr other) {
    int a = Index(want), b = Index(other);
    if (a < 0 || b < 0) return false;
    RECT ra, rb;
    GetWindowRect(want, out ra); GetWindowRect(other, out rb);
    bool overlap = ra.Left < rb.Right && rb.Left < ra.Right && ra.Top < rb.Bottom && rb.Top < ra.Bottom;
    return overlap && b < a;
  }
  public static int Index(IntPtr want) {
    int idx = 0;
    for (IntPtr h = GetWindowTop(); h != IntPtr.Zero; h = Next(h), idx++) if (h == want) return idx;
    return -1;
  }
  // the first visible, non-ours window above ours that overlaps it
  public static string AboveList(IntPtr want) {
    RECT me; GetWindowRect(want, out me);
    var sb = new StringBuilder(); int idx = 0;
    for (IntPtr h = GetWindowTop(); h != IntPtr.Zero; h = Next(h), idx++) {
      if (h == want) break;
      if (!IsWindowVisible(h)) continue;
      RECT r; GetWindowRect(h, out r);
      if (r.Right <= me.Left || r.Left >= me.Right || r.Bottom <= me.Top || r.Top >= me.Bottom) continue;
      var b = new StringBuilder(128); GetClassName(h, b, 128);
      bool top = ((long)GetWindowLong(h, -20) & 0x8L) != 0;
      sb.Append("z#" + idx + ":" + b.ToString() + "(tm=" + (top ? 1 : 0) + ") ");
    }
    return sb.Length == 0 ? "-" : sb.ToString();
  }
}
"@
[void][ZF]::SetProcessDpiAwarenessContext([IntPtr](-4))

$hStrip = [ZF]::ByClass("DockStripWindow")
if ($hStrip -eq [IntPtr]::Zero) { throw "DockStripWindow not found - is dock running?" }
$r = New-Object ZF+RECT; [void][ZF]::GetWindowRect($hStrip, [ref]$r)
$pass = 0; $fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { $script:pass++; Write-Output ("  PASS  " + $name + "   " + $detail) }
    else { $script:fail++; Write-Output ("  FAIL  " + $name + "   " + $detail) }
}

Write-Output ("strip rect {0},{1}-{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom)
Write-Output ("A/B baseline: " + [ZF]::Where($hStrip) + "  above=" + [ZF]::AboveList($hStrip))

# ---- A: a new topmost window over the dock, nobody touches the dock afterwards ----------
$f = New-Object System.Windows.Forms.Form
$f.Text = "zfix A: topmost newcomer"
$f.TopMost = $true
$f.StartPosition = 'Manual'
$f.FormBorderStyle = 'SizableToolWindow'
$f.Size = New-Object System.Drawing.Size(500, 300)
$f.Location = New-Object System.Drawing.Point(($r.Left + 150), ($r.Top + 10))
$f.Show(); [void][System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 250
$hTest = $f.Handle
Write-Output ""
Write-Output "== A. a new topmost window appeared over the strip =="
Write-Output ("   test  " + [ZF]::Where($hTest))
Write-Output ("   strip " + [ZF]::Where($hStrip))
Start-Sleep -Milliseconds $Settle
Write-Output ("   after ${Settle}ms with nobody touching the dock:")
Write-Output ("   strip " + [ZF]::Where($hStrip) + "  above=" + [ZF]::AboveList($hStrip))
Check "A  watchdog climbed back above the newcomer" (-not [ZF]::Above($hStrip, $hTest)) ([ZF]::Where($hStrip))

# ---- B: the strip loses WS_EX_TOPMOST ------------------------------------------------
Write-Output ""
Write-Output "== B. the strip is demoted behind its back (HWND_NOTOPMOST) =="
[void][ZF]::SetWindowPos($hStrip, [ZF]::NOTOPMOST, 0, 0, 0, 0, ([ZF]::NOMOVE -bor [ZF]::NOSIZE -bor [ZF]::NOACTIVATE))
Start-Sleep -Milliseconds 250
Write-Output ("   strip " + [ZF]::Where($hStrip))
Start-Sleep -Milliseconds $Settle
Write-Output ("   after ${Settle}ms: " + [ZF]::Where($hStrip))
$top = ([ZF]::Where($hStrip) -match 'topmost=1')
Check "B  watchdog restored WS_EX_TOPMOST" $top ([ZF]::Where($hStrip))
Check "B  and is above the newcomer again" (-not [ZF]::Above($hStrip, $hTest)) ([ZF]::Where($hStrip))

$f.Close(); $f.Dispose()
Start-Sleep -Milliseconds 300

# ---- C: capture overlay ---------------------------------------------------------------
if (-not $SkipCapture) {
    Write-Output ""
    Write-Output "== C. Snipping Tool overlay comes to the front =="
    $before = [ZF]::Where($hStrip)
    Start-Process 'ms-screenclip:'
    Start-Sleep -Milliseconds 1800
    $during = [ZF]::Where($hStrip)
    $aboveDuring = [ZF]::AboveList($hStrip)
    Write-Output ("   before: " + $before)
    Write-Output ("   during: " + $during + "  above=" + $aboveDuring)
    Check "C  dock stepped below the capture overlay" ($during -match 'topmost=0') $during
    # D: our own show paths assert HWND_TOPMOST all over the place (the companion fading in when
    # the pointer reaches the menus next to the dock is what the user hit with QQ's snip).
    # Simulate one of those asserts while the overlay is up: it must be undone, not left on top.
    [void][ZF]::SetWindowPos($hStrip, [ZF]::TOPMOST, 0, 0, 0, 0, ([ZF]::NOMOVE -bor [ZF]::NOSIZE -bor [ZF]::NOACTIVATE))
    Start-Sleep -Milliseconds 450
    $afterAssert = [ZF]::Where($hStrip)
    Write-Output ("   after a forced HWND_TOPMOST assert: " + $afterAssert)
    Check "D  a re-assert during the snip is undone" ($afterAssert -match 'topmost=0') $afterAssert

    # E: the reported QQ case. The toolbar / its menus sit right next to the dock, so the pointer
    # ends up inside the dock's fade radius while the snip is still up: the companion fades in and
    # its show path used to lift the whole dock back over the selection box. Park the cursor on the
    # companion and make sure both stay non-topmost.
    $hComp = [ZF]::ByClass("DockTrayBarWindow")
    if ($hComp -ne [IntPtr]::Zero) {
        $cr = New-Object ZF+RECT; [void][ZF]::GetWindowRect($hComp, [ref]$cr)
        $save = New-Object ZF+POINT; [void][ZF]::GetCursorPos([ref]$save)
        [void][ZF]::SetCursorPos([int](($cr.Left + $cr.Right) / 2), [int](($cr.Top + $cr.Bottom) / 2))
        Start-Sleep -Milliseconds 900
        $compNow = [ZF]::Where($hComp)
        $stripNow = [ZF]::Where($hStrip)
        Write-Output ("   cursor parked on the companion: companion " + $compNow)
        Write-Output ("                                  strip     " + $stripNow)
        Check "E  companion fading in does not lift the dock" (($compNow -match 'topmost=0') -and ($stripNow -match 'topmost=0')) $stripNow
        [void][ZF]::SetCursorPos($save.X, $save.Y)
    }
    # close it: SnippingTool accepts Escape; killing is the fallback
    Add-Type -AssemblyName System.Windows.Forms
    try { [System.Windows.Forms.SendKeys]::SendWait("{ESC}") } catch {}
    Start-Sleep -Milliseconds 500
    $snip = Get-Process SnippingTool -ErrorAction SilentlyContinue
    if ($snip) { $snip | Stop-Process -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 1600
    $after = [ZF]::Where($hStrip) + "  above=" + [ZF]::AboveList($hStrip)
    Write-Output ("   after:  " + $after)
    Check "C  dock is topmost again once the snip is gone" ($after -match 'topmost=1') $after
}

Write-Output ""
Write-Output ("done: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
