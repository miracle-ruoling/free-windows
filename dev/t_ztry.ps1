# Task 1 experiment: can a *later* topmost window legally cover ours, and does re-asserting
# HWND_TOPMOST put us back on top?  This is the mechanised version of the user's report
# ("a newly summoned window covers the dock for a while").
#
#   .\t_ztry.ps1            # run the whole experiment, closes its test window at the end
#   .\t_ztry.ps1 -Hold 0    # same, but nothing stays on screen afterwards
#
# It never touches the dock process: everything is done from this probe with SetWindowPos.
param([int]$Hold = 0)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class ZT {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static readonly IntPtr TOPMOST = new IntPtr(-1);
  public static readonly IntPtr NOTOPMOST = new IntPtr(-2);
  public const uint NOMOVE = 0x2, NOSIZE = 0x1, NOACTIVATE = 0x10, NOZORDER = 0x4;

  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  // FindWindowW does not match a class registered by another process here (returns 0 even
  // though the window is in EnumWindows), so look it up by enumeration instead.
  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      var b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static string Where(IntPtr want) {
    int idx = 0;
    for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero; h = GetWindow(h, 2)) {
      if (h == want) {
        RECT r; GetWindowRect(want, out r);
        bool top = ((long)GetWindowLong(want, -20) & 0x8L) != 0;
        return "z#" + idx + " topmost=" + top + " vis=" + IsWindowVisible(want) +
               " " + r.Left + "," + r.Top + "-" + r.Right + "," + r.Bottom;
      }
      idx++;
      if (idx > 4000) break;
    }
    return "(not in the z-order at all)";
  }
  // every visible window above `want` that overlaps it, in z-order
  public static string Above(IntPtr want) {
    RECT me; GetWindowRect(want, out me);
    var sb = new StringBuilder(); int n = 0;
    int idx = 0;
    for (IntPtr h = GetTopWindow(IntPtr.Zero); h != IntPtr.Zero; h = GetWindow(h, 2), idx++) {
      if (h == want) break;
      if (!IsWindowVisible(h)) continue;
      RECT r; GetWindowRect(h, out r);
      if (r.Right <= me.Left || r.Left >= me.Right || r.Bottom <= me.Top || r.Top >= me.Bottom) continue;
      var b = new StringBuilder(128); GetClassName(h, b, 128);
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool top = ((long)GetWindowLong(h, -20) & 0x8L) != 0;
      sb.Append("    z#" + idx + " " + b.ToString() + " pid=" + pid + " topmost=" + (top ? 1 : 0) +
                " " + r.Left + "," + r.Top + "-" + r.Right + "," + r.Bottom + "\n");
      n++;
      if (n > 6) break;
    }
    return sb.ToString().Length == 0 ? "    (nothing visible above it that overlaps)\n" : sb.ToString();
  }
}
"@
[void][ZT]::SetProcessDpiAwarenessContext([IntPtr](-4))

$strip = (Get-Process dock -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $strip) { throw "dock is not running" }
$hStrip = [ZT]::ByClass("DockStripWindow")
if ($hStrip -eq [IntPtr]::Zero) { throw "DockStripWindow not found" }
$r = New-Object ZT+RECT
[void][ZT]::GetWindowRect($hStrip, [ref]$r)
Write-Output ("strip rect {0},{1}-{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom)

Write-Output ""
Write-Output "== 1. before =="
Write-Output ("  strip  " + [ZT]::Where($hStrip))
Write-Output "  above strip:"
Write-Output ([ZT]::Above($hStrip))

# a stand-in for "a newly summoned window", 500x300, laid over the strip's middle
$f = New-Object System.Windows.Forms.Form
$f.Text = "zwatch test window (topmost)"
$f.TopMost = $true
$f.StartPosition = 'Manual'
$f.FormBorderStyle = 'SizableToolWindow'
$f.Size = New-Object System.Drawing.Size(500, 300)
$f.Location = New-Object System.Drawing.Point(($r.Left + 150), ($r.Top + 10))
$f.Show()
[void][System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 400
$hTest = $f.Handle

Write-Output ""
Write-Output "== 2. a new topmost window is on screen =="
Write-Output ("  test   " + [ZT]::Where($hTest) + "  (TopMost=true)")
Write-Output ("  strip  " + [ZT]::Where($hStrip))
Write-Output "  above strip:"
Write-Output ([ZT]::Above($hStrip))

Write-Output ""
Write-Output "== 3. re-assert the strip with SetWindowPos(HWND_TOPMOST, NOMOVE|NOSIZE|NOACTIVATE) =="
$ok = [ZT]::SetWindowPos($hStrip, [ZT]::TOPMOST, 0, 0, 0, 0, ([ZT]::NOMOVE -bor [ZT]::NOSIZE -bor [ZT]::NOACTIVATE))
Write-Output ("  SetWindowPos -> " + $ok)
Start-Sleep -Milliseconds 250
Write-Output ("  strip  " + [ZT]::Where($hStrip))
Write-Output ("  test   " + [ZT]::Where($hTest))
Write-Output "  above strip:"
Write-Output ([ZT]::Above($hStrip))

Write-Output ""
Write-Output "== 4. does a *demoted* strip stay demoted? SetWindowPos(HWND_NOTOPMOST) then check =="
[void][ZT]::SetWindowPos($hStrip, [ZT]::NOTOPMOST, 0, 0, 0, 0, ([ZT]::NOMOVE -bor [ZT]::NOSIZE -bor [ZT]::NOACTIVATE))
Start-Sleep -Milliseconds 250
Write-Output ("  strip  " + [ZT]::Where($hStrip))
Write-Output ("  test   " + [ZT]::Where($hTest))
Write-Output "  above strip:"
Write-Output ([ZT]::Above($hStrip))

Write-Output ""
Write-Output "== 5. restore the strip to topmost (leave the system as we found it) =="
[void][ZT]::SetWindowPos($hStrip, [ZT]::TOPMOST, 0, 0, 0, 0, ([ZT]::NOMOVE -bor [ZT]::NOSIZE -bor [ZT]::NOACTIVATE))
Start-Sleep -Milliseconds 250
Write-Output ("  strip  " + [ZT]::Where($hStrip))
Write-Output ("  test   " + [ZT]::Where($hTest))

if ($Hold -gt 0) {
    Write-Output ""
    Write-Output "test window stays for $Hold s ..."
    Start-Sleep -Seconds $Hold
}
$f.Close(); $f.Dispose()
Write-Output ""
Write-Output "done (test window closed)"
