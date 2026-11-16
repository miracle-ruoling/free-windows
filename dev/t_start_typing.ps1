# Start menu: can the search box take focus / typing?
#   -Mode external : send Ctrl+Esc from this script (dock not involved)
#   -Mode dock     : click the fixed Windows cell on the strip (dock sends Ctrl+Esc)
# Prints, for each sample: foreground window, the GUI thread's focus/capture window, the
# Start host windows, the UIA tree of the panel (search box rect + focus) and who owns
# the pixel under the search box (WindowFromPoint). Optionally types text and reports
# what the search box holds afterwards.
#   -Type "abc"   : send those keys after the panel is up
#   -Out prefix   : screenshot prefix (writes <prefix>_closed.png / _open.png / _typed.png)
param(
    [ValidateSet("external", "dock")][string]$Mode = "external",
    [string]$Type = "",
    [string]$Out = "start_typing",
    [switch]$KeepOpen
)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public class ST {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO g);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public int cbSize; public int flags;
    public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
    public RECT rcCaret;
  }
  public class Info {
    public IntPtr H; public string Cls = ""; public string Txt = ""; public uint Pid;
    public bool Vis; public RECT R; public int Cloaked;
  }

  public static string Name(IntPtr h) {
    if (h == IntPtr.Zero) return "(null)";
    StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
    StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200);
    uint p; GetWindowThreadProcessId(h, out p);
    RECT r; GetWindowRect(h, out r);
    int cl = -1; DwmGetWindowAttribute(h, 14, out cl, 4);
    return string.Format("{0} pid={1} cls={2} txt='{3}' vis={4} cloaked={5} rect={6},{7} {8}x{9}",
      h.ToInt64(), p, b.ToString(), t.ToString(), IsWindowVisible(h), cl,
      r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
  }
  public static string FocusInfo() {
    IntPtr fg = GetForegroundWindow();
    uint pid = 0;
    uint tid = GetWindowThreadProcessId(fg, out pid);
    GUITHREADINFO g = new GUITHREADINFO();
    g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
    bool ok = GetGUIThreadInfo(tid, ref g);
    string s = "fg: " + Name(fg) + "\n";
    s += "  tid=" + tid + " guiInfo=" + ok + " active=" + g.hwndActive.ToInt64() +
         " focus=" + g.hwndFocus.ToInt64() + " capture=" + g.hwndCapture.ToInt64() +
         " menuOwner=" + g.hwndMenuOwner.ToInt64() + "\n";
    if (g.hwndFocus != IntPtr.Zero && g.hwndFocus != fg) s += "  focusWin: " + Name(g.hwndFocus) + "\n";
    if (g.hwndCapture != IntPtr.Zero && g.hwndCapture != fg) s += "  captureWin: " + Name(g.hwndCapture) + "\n";
    return s;
  }
  public static List<Info> All() {
    List<Info> l = new List<Info>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      Info i = new Info(); i.H = h;
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200); i.Cls = b.ToString();
      StringBuilder t = new StringBuilder(200); GetWindowText(h, t, 200); i.Txt = t.ToString();
      uint p = 0; GetWindowThreadProcessId(h, out p); i.Pid = p;
      i.Vis = IsWindowVisible(h);
      RECT r; GetWindowRect(h, out r); i.R = r;
      int cl = -1; DwmGetWindowAttribute(h, 14, out cl, 4); i.Cloaked = cl;
      l.Add(i);
      return true; }, IntPtr.Zero);
    return l;
  }
  public static string Owner(int x, int y) {
    POINT p; p.X = x; p.Y = y;
    IntPtr h = WindowFromPoint(p);
    IntPtr root = GetAncestor(h, 2);
    return "  WindowFromPoint(" + x + "," + y + ") = " + h.ToInt64() + " root=" + root.ToInt64() + "\n    " + Name(root);
  }
  public static Bitmap Shot() {
    Bitmap bmp = new Bitmap(GetSystemMetrics(0), GetSystemMetrics(1), PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(bmp))
      g.CopyFromScreen(0, 0, 0, 0, bmp.Size, CopyPixelOperation.SourceCopy);
    return bmp;
  }
  public static string DiffBox(Bitmap a, Bitmap b, int thresh) {
    int w = a.Width, h = a.Height;
    Rectangle rect = new Rectangle(0, 0, w, h);
    BitmapData da = a.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    BitmapData db = b.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    int stride = da.Stride;
    byte[] ra = new byte[stride * h];
    byte[] rb = new byte[stride * h];
    Marshal.Copy(da.Scan0, ra, 0, ra.Length);
    Marshal.Copy(db.Scan0, rb, 0, rb.Length);
    a.UnlockBits(da); b.UnlockBits(db);
    int minx = w, miny = h, maxx = -1, maxy = -1, n = 0;
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        int o = row + x * 4;
        int d = Math.Abs(ra[o] - rb[o]) + Math.Abs(ra[o+1] - rb[o+1]) + Math.Abs(ra[o+2] - rb[o+2]);
        if (d > thresh) {
          n++;
          if (x < minx) minx = x; if (x > maxx) maxx = x;
          if (y < miny) miny = y; if (y > maxy) maxy = y;
        }
      }
    }
    if (maxx < 0) return "changed=0";
    return string.Format("changed={0} drawnBox={1},{2}-{3},{4}", n, minx, miny, maxx + 1, maxy + 1);
  }
  public static void Save(Bitmap b, string path) { b.Save(path, ImageFormat.Png); }
  public static void CtrlEsc() {
    keybd_event(0x11, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(45);
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(45);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(45);
    keybd_event(0x11, 0, 2, UIntPtr.Zero);
  }
  public static void Esc() {
    keybd_event(0x1B, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(0x1B, 0, 2, UIntPtr.Zero);
  }
  public static void Key(byte vk) {
    keybd_event(vk, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(40);
    keybd_event(vk, 0, 2, UIntPtr.Zero);
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(90);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static IntPtr StartHost(string[] names) {
    List<uint> pids = new List<uint>();
    foreach (string n in names) {
      System.Diagnostics.Process[] ps = System.Diagnostics.Process.GetProcessesByName(n);
      foreach (System.Diagnostics.Process p in ps) pids.Add((uint)p.Id);
    }
    IntPtr found = IntPtr.Zero;
    foreach (Info i in All()) {
      if (!pids.Contains(i.Pid)) continue;
      if (i.Cls == "Windows.UI.Core.CoreWindow") { found = i.H; break; }
    }
    return found;
  }
}
'@
[void][ST]::SetProcessDpiAwarenessContext([IntPtr](-4))
$dir = $PSScriptRoot

function ShotFile([string]$tag) {
    $b = [ST]::Shot()
    [ST]::Save($b, (Join-Path $dir ($Out + "_" + $tag + ".png")))
    return $b
}
$script:hostPids = @()
foreach ($n in @('StartMenuExperienceHost', 'SearchHost', 'ShellExperienceHost', 'ShellHost')) {
    $script:hostPids += @((Get-Process $n -ErrorAction SilentlyContinue).Id | ForEach-Object { [int]$_ })
}
function UiaTop {
    # The panel hosts are not enumerable with EnumWindows (documented), so ask UIA for the
    # desktop's children and keep the ones owned by the shell hosts we care about.
    $res = @()
    try {
        $kids = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($e in $kids) {
            $procId = $e.Current.ProcessId
            if ($script:hostPids -notcontains [int]$procId) { continue }
            $r = $e.Current.BoundingRectangle
            Write-Output ("  uiaTop pid=" + $procId + " cls=" + $e.Current.ClassName + " name='" + $e.Current.Name + "' rect=" + [int]$r.X + "," + [int]$r.Y + " " + [int]$r.Width + "x" + [int]$r.Height)
            $res += $e
        }
    } catch { Write-Output ("  UIA top error: " + $_.Exception.Message) }
    return $res
}
function UiaTree($root) {
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        Write-Output ("  UIA descendants=" + $all.Count)
        $i = 0
        foreach ($e in $all) {
            $i++
            if ($i -gt 45) { Write-Output "  ... (truncated)"; break }
            $ct = $e.Current.ControlType.ProgrammaticName
            $nm = $e.Current.Name
            if ($nm.Length -gt 40) { $nm = $nm.Substring(0, 40) }
            $r = $e.Current.BoundingRectangle
            Write-Output ("    " + $ct + " cls=" + $e.Current.ClassName + " name='" + $nm + "' rect=" + [int]$r.X + "," + [int]$r.Y + " " + [int]$r.Width + "x" + [int]$r.Height + " kbFocus=" + $e.Current.HasKeyboardFocus + " focusable=" + $e.Current.IsKeyboardFocusable)
        }
    } catch { Write-Output ("  UIA error: " + $_.Exception.Message) }
}
function Edits($root) {
    try {
        $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Edit)
        $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        Write-Output ("  UIA edits=" + $edits.Count)
        foreach ($e in $edits) {
            $val = ''
            try { $val = ([System.Windows.Automation.ValuePattern]$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).Current.Value } catch { $val = '<no value pattern>' }
            $r = $e.Current.BoundingRectangle
            Write-Output ("    edit name='" + $e.Current.Name + "' value='" + $val + "' rect=" + [int]$r.X + "," + [int]$r.Y + " " + [int]$r.Width + "x" + [int]$r.Height + " kbFocus=" + $e.Current.HasKeyboardFocus)
            return $e
        }
    } catch { Write-Output ("  UIA edit error: " + $_.Exception.Message) }
    return $null
}
function DumpState([string]$tag) {
    Write-Output ("=== " + $tag + " ===")
    Write-Output ([ST]::FocusInfo().TrimEnd())
    try {
        $fe = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($fe -ne $null) {
            $fr = $fe.Current.BoundingRectangle
            Write-Output ("  UIA focused: pid=" + $fe.Current.ProcessId + " cls=" + $fe.Current.ClassName + " type=" + $fe.Current.ControlType.ProgrammaticName + " name='" + $fe.Current.Name + "' rect=" + [int]$fr.X + "," + [int]$fr.Y + " " + [int]$fr.Width + "x" + [int]$fr.Height)
        } else { Write-Output "  UIA focused: (null)" }
    } catch { Write-Output ("  UIA focused error: " + $_.Exception.Message) }
    $tops = @(UiaTop)
    if ($tops.Count -eq 0) { Write-Output "  (no Start/Search/Settings top-level UIA element)" }
    return $tops
}
function WinCell {
    $strip = [IntPtr]::Zero
    foreach ($w in [ST]::All()) { if ($w.Cls -eq "DockStripWindow") { $strip = $w.H; break } }
    if ($strip -eq [IntPtr]::Zero) { return $null }
    $r = New-Object ST+RECT
    [void][ST]::GetWindowRect($strip, [ref]$r)
    $log = Get-Content (Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log') -Tail 400 |
           Select-String -Pattern "layout: " | Select-Object -Last 1
    if (-not $log -or $log.Line -notmatch "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)") { return $null }
    $cx = $r.Left + [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $cy = $r.Top + [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    return @($cx, $cy, $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top))
}

Write-Output ("mode=" + $Mode)
[ST]::Esc(); Start-Sleep -Milliseconds 700
$closed = ShotFile "closed"
DumpState "before (Start closed)"
$cell = WinCell
if ($cell) { Write-Output ("strip=" + $cell[2] + "," + $cell[3] + " " + $cell[4] + "x" + $cell[5] + "  win cell -> " + $cell[0] + "," + $cell[1]) }

if ($Mode -eq "dock") {
    if (-not $cell) { Write-Output "no win cell - cannot click the strip"; exit 1 }
    [void][ST]::SetCursorPos($cell[0], $cell[1]); Start-Sleep -Milliseconds 400
    [ST]::Click($cell[0], $cell[1])
    Write-Output "clicked the Windows cell"
} else {
    [ST]::CtrlEsc()
    Write-Output "sent Ctrl+Esc from this script"
}

Start-Sleep -Milliseconds 260
[void](DumpState "+260ms")
Start-Sleep -Milliseconds 400
Write-Output ("=== +660ms ===")
Write-Output ([ST]::FocusInfo().TrimEnd())
try {
    $fe = [System.Windows.Automation.AutomationElement]::FocusedElement
    if ($fe -ne $null) {
        $fr = $fe.Current.BoundingRectangle
        Write-Output ("  UIA focused: pid=" + $fe.Current.ProcessId + " cls=" + $fe.Current.ClassName + " type=" + $fe.Current.ControlType.ProgrammaticName + " name='" + $fe.Current.Name + "' rect=" + [int]$fr.X + "," + [int]$fr.Y + " " + [int]$fr.Width + "x" + [int]$fr.Height)
    } else { Write-Output "  UIA focused: (null)" }
} catch { Write-Output ("  UIA focused error: " + $_.Exception.Message) }
$tops = @(UiaTop)
$panel = $null
if ($tops.Count -gt 0) {
    # the panel is the element that actually has a box (the parked ones are 0x0 / at 32767)
    foreach ($t in $tops) { $r = $t.Current.BoundingRectangle; if ($r.Width -gt 100 -and $r.Height -gt 100 -and $r.X -lt 30000) { $panel = $t; break } }
    if ($panel -eq $null) { $panel = $tops[0] }
}
$open = ShotFile "open"
Write-Output ("drawn pixels vs closed: " + [ST]::DiffBox($closed, $open, 24))

$editEl = $null
if ($panel -ne $null) {
    Write-Output ("panel element: pid=" + $panel.Current.ProcessId + " cls=" + $panel.Current.ClassName + " name='" + $panel.Current.Name + "'")
    UiaTree $panel
    $editEl = Edits $panel
}
if ($editEl -ne $null) {
    $r = $editEl.Current.BoundingRectangle
    $cx = [int]($r.X + $r.Width / 2); $cy = [int]($r.Y + $r.Height / 2)
    Write-Output ("search box center=" + $cx + "," + $cy)
    Write-Output ([ST]::Owner($cx, $cy))
    Write-Output ([ST]::Owner([int]$r.X + 30, $cy))
} else {
    Write-Output "no search box found via UIA"
}

if ($Type) {
    # never type into an app we did not open: only go ahead while the shell owns the focus
    $fg = [ST]::FocusInfo()
    $ok = $false
    foreach ($p in $script:hostPids) { if ($fg -match ("pid=" + $p + " ")) { $ok = $true } }
    if (-not $ok) {
        Write-Output "REFUSING to type - the shell does not own the foreground:"
        Write-Output $fg
    } else {
        Start-Sleep -Milliseconds 200
        foreach ($ch in $Type.ToCharArray()) { [ST]::Key([byte][char]([string]$ch).ToUpper()); Start-Sleep -Milliseconds 130 }
        Start-Sleep -Milliseconds 500
        Write-Output ("after typing '" + $Type + "':")
        [void](DumpState "after typing")
        if ($panel -ne $null) { [void](Edits $panel) }
        $typed = ShotFile "typed"
        Write-Output ("drawn pixels vs closed: " + [ST]::DiffBox($closed, $typed, 24))
    }
}

if (-not $KeepOpen) { [ST]::Esc(); Start-Sleep -Milliseconds 400 }
