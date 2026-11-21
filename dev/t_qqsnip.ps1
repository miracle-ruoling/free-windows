# Task 1: what does QQ's snip (Ctrl+Alt+X) look like to the dock, and does the dock stay below it
# while the pointer wanders onto the toolbar / onto the dock itself?
#
#   .\t_qqsnip.ps1 -Mode probe    # Ctrl+Alt+X, dump who is above us, Escape. Nothing is selected.
#   .\t_qqsnip.ps1 -Mode flow     # Ctrl+Alt+X, drag a box over the dock, then wander the cursor
#                                 # onto the toolbar and onto the dock, sampling our windows' flags
#
# Nothing here clicks anything of ours: the pointer is only moved, and the box is dragged over the
# empty area the dock occupies.
param([ValidateSet("probe", "flow")][string]$Mode = "probe", [int]$OpenMs = 1200)
$ErrorActionPreference = 'Continue'
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class QQ {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static IntPtr ByClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  public static string Info(IntPtr want) {
    if (want == IntPtr.Zero) return "(absent)";
    RECT r; GetWindowRect(want, out r);
    bool top = ((long)GetWindowLong(want, -20) & 0x8L) != 0;
    return "tm=" + (top ? 1 : 0) + " vis=" + (IsWindowVisible(want) ? 1 : 0) +
           " " + r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top);
  }
  // visible windows above `want` that overlap it
  public static string Above(IntPtr want) {
    RECT me; if (!GetWindowRect(want, out me)) return "?";
    var sb = new StringBuilder(); int idx = 0;
    for (IntPtr h = GetWindowTop(); h != IntPtr.Zero; h = Next(h), idx++) {
      if (h == want) break;
      if (!IsWindowVisible(h)) continue;
      RECT r; if (!GetWindowRect(h, out r)) continue;
      if (r.Right <= me.Left || r.Left >= me.Right || r.Bottom <= me.Top || r.Top >= me.Bottom) continue;
      var b = new StringBuilder(128); GetClassName(h, b, 128);
      var t = new StringBuilder(128); GetWindowText(h, t, 60);
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool top = ((long)GetWindowLong(h, -20) & 0x8L) != 0;
      int ck; bool cloak = DwmGetWindowAttribute(h, 14, out ck, 4) == 0 && ck != 0;
      sb.Append("z#" + idx + ":" + b + "(pid=" + pid + ",tm=" + (top ? 1 : 0) + (cloak ? ",cloaked" : "") +
                "," + r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top) + ") ");
    }
    return sb.Length == 0 ? "-" : sb.ToString();
  }
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  public static IntPtr GetWindowTop() { return GetTopWindow(IntPtr.Zero); }
  public static IntPtr Next(IntPtr h) { return GetWindow(h, 2); }

  // every visible+topmost window that covers (nearly) a whole monitor: the snip overlay candidates
  public static string Overlays() {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h)) return true;
      if (((long)GetWindowLong(h, -20) & 0x8L) == 0) return true;
      RECT r; if (!GetWindowRect(h, out r)) return true;
      if (r.Right - r.Left < 1900 || r.Bottom - r.Top < 1000) return true;
      var b = new StringBuilder(128); GetClassName(h, b, 128);
      var t = new StringBuilder(128); GetWindowText(h, t, 60);
      uint pid; GetWindowThreadProcessId(h, out pid);
      int ck; bool cloak = DwmGetWindowAttribute(h, 14, out ck, 4) == 0 && ck != 0;
      sb.Append("   cls=" + b + " pid=" + pid + " cloak=" + (cloak ? 1 : 0) + " '" + t + "'\n");
      return true;
    }, IntPtr.Zero);
    return sb.Length == 0 ? "   (none)\n" : sb.ToString();
  }

  public static void Key(byte vk, bool up) { keybd_event(vk, 0, up ? 2u : 0u, UIntPtr.Zero); }
  public static void Click(uint downFlag, uint upFlag) {
    mouse_event(downFlag, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(upFlag, 0, 0, 0, UIntPtr.Zero);
  }
}
"@
[void][QQ]::SetProcessDpiAwarenessContext([IntPtr](-4))

$hStrip = [QQ]::ByClass("DockStripWindow")
$hComp = [QQ]::ByClass("DockTrayBarWindow")
$hGroup = [QQ]::ByClass("DockGroupBoxWindow")
function State($tag) {
    Write-Output ("{0,-22} strip {1}" -f $tag, [QQ]::Info($hStrip))
    Write-Output ("{0,-22} tray  {1}" -f "", [QQ]::Info($hComp))
}
$save = New-Object QQ+POINT
[void][QQ]::GetCursorPos([ref]$save)
$sr = New-Object QQ+RECT; [void][QQ]::GetWindowRect($hStrip, [ref]$sr)

Write-Output "== before =="
State "  "
Write-Output ("  above strip: " + [QQ]::Above($hStrip))

Write-Output ""
Write-Output "== Ctrl+Alt+X =="
[QQ]::Key(0x11, $false); [QQ]::Key(0x12, $false); Start-Sleep -Milliseconds 40
[QQ]::Key(0x58, $false); Start-Sleep -Milliseconds 60; [QQ]::Key(0x58, $true)
Start-Sleep -Milliseconds 60
[QQ]::Key(0x12, $true); [QQ]::Key(0x11, $true)
Start-Sleep -Milliseconds $OpenMs

Write-Output "  fullscreen topmost windows on screen now:"
Write-Output ([QQ]::Overlays())
State "  after open"
Write-Output ("  above strip: " + [QQ]::Above($hStrip))

if ($Mode -eq "flow") {
    # Never drag unless QQ's overlay is really up: without it the drag would land in whatever
    # window happens to be in front (a text selection at best, a window move at worst).
    $ovl = [QQ]::Overlays()
    if ($ovl -match '\(none\)') {
        Write-Output ""
        Write-Output "!! no fullscreen topmost window appeared - QQ's snip did not open; skipping the drag"
        [QQ]::Key(0x1B, $false); Start-Sleep -Milliseconds 40; [QQ]::Key(0x1B, $true)
        exit 2
    }
    # drag a box over the empty area the dock sits in (top-left of the strip to a bit past it)
    $x0 = $sr.Left - 60; $y0 = 2
    $x1 = $sr.Right + 40; $y1 = $sr.Bottom + 60
    Write-Output ""
    Write-Output ("== drag a selection $x0,$y0 -> $x1,$y1 (over the dock) ==")
    [void][QQ]::SetCursorPos($x0, $y0); Start-Sleep -Milliseconds 120
    [QQ]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)     # LEFTDOWN
    for ($i = 1; $i -le 10; $i++) {
        [void][QQ]::SetCursorPos([int]($x0 + ($x1 - $x0) * $i / 10), [int]($y0 + ($y1 - $y0) * $i / 10))
        Start-Sleep -Milliseconds 40
    }
    [QQ]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)     # LEFTUP  -> box done, toolbar appears
    Start-Sleep -Milliseconds 700
    State "  after selection"
    Write-Output ("  above strip: " + [QQ]::Above($hStrip))

    # now do what the user does: wander over the toolbar / the menus below the box, then come back
    $probes = @(
        @{ n = "toolbar area (below box)"; x = [int](($x0 + $x1) / 2); y = $y1 + 22 },
        @{ n = "over the companion";       x = 1400; y = 40 },
        @{ n = "over the strip";           x = [int](($sr.Left + $sr.Right) / 2); y = 40 },
        @{ n = "box centre again";         x = [int](($x0 + $x1) / 2); y = 30 }
    )
    foreach ($p in $probes) {
        [void][QQ]::SetCursorPos($p.x, $p.y)
        Start-Sleep -Milliseconds 700
        State ("  at " + $p.n)
    }
}

Write-Output ""
Write-Output "== Escape (cancel the snip) =="
[QQ]::Key(0x1B, $false); Start-Sleep -Milliseconds 40; [QQ]::Key(0x1B, $true)
Start-Sleep -Milliseconds 900
State "  after escape"
[void][QQ]::SetCursorPos($save.X, $save.Y)
