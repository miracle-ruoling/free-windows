# Right click the strip's Windows button and report where the Win+X popup ended up,
# next to the anchor published by the dock.
param([switch]$KeepOpen)
Add-Type -Language CSharp @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class WX3 {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr OpenFileMapping(uint a, bool i, string n);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr MapViewOfFile(IntPtr m, uint a, uint hi, uint lo, UIntPtr bytes);
  [DllImport("kernel32.dll")] public static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Entry {
    public uint kind; public uint flags; public int left, top, right, bottom; public int gapPx;
    public uint armedAtMs; public int pad0, pad1, pad2;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Table {
    public uint magic; public uint version; public uint count; public uint updatedMs;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)] public Entry[] entries;
  }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == cls) { found = h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
  public static List<string> Popups() {
    List<string> l = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() != "Xaml_WindowedPopupClass") return true;
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(128); GetWindowText(h, t, 128);
      RECT r; GetWindowRect(h, out r);
      uint pid; GetWindowThreadProcessId(h, out pid);
      l.Add(string.Format("h={0} pid={1} txt='{2}' rect={3},{4} {5}x{6}", h.ToInt64(), pid, t, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top));
      return true; }, IntPtr.Zero);
    return l;
  }
  public static Entry Anchor(uint kind) {
    IntPtr map = OpenFileMapping(0x0004, false, @"Local\DockAnchor_v1");
    if (map == IntPtr.Zero) return new Entry();
    IntPtr view = MapViewOfFile(map, 0x0004, 0, 0, (UIntPtr)Marshal.SizeOf(typeof(Table)));
    Entry e = new Entry();
    if (view != IntPtr.Zero) {
      Table t = (Table)Marshal.PtrToStructure(view, typeof(Table));
      if (kind >= 1 && kind <= 16) e = t.entries[kind - 1];
      UnmapViewOfFile(view);
    }
    CloseHandle(map);
    return e;
  }
}
"@
[void][WX3]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Esc {
    [WX3]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
    [WX3]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
}
$strip = [WX3]::Find('DockStripWindow')
$r = New-Object WX3+RECT
[void][WX3]::GetWindowRect($strip, [ref]$r)
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
$line = ($txt -split "`r?`n") | Where-Object { $_ -match 'layout: ' } | Select-Object -Last 1
[void]($line -match "win=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)")
$cx = $r.Left + [int]((([int]$Matches[1]) + ([int]$Matches[3])) / 2)
$cy = $r.Top + [int]((([int]$Matches[2]) + ([int]$Matches[4])) / 2)
Write-Output ("strip " + $r.Left + "," + $r.Top + "  click target " + $cx + "," + $cy)
$e = [WX3]::Anchor(4)
Write-Output ("anchor kind=4 rect=" + $e.left + "," + $e.top + "-" + $e.right + "," + $e.bottom + " gap=" + $e.gapPx + " flags=" + $e.flags)
Write-Output "--- popups before ---"
[WX3]::Popups() | ForEach-Object { Write-Output ("  " + $_) }
Esc; Start-Sleep -Milliseconds 700
[void][WX3]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 400
[WX3]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 70
[WX3]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
Write-Output "right clicked"
Start-Sleep -Milliseconds 1100
Write-Output "--- popups after ---"
[WX3]::Popups() | ForEach-Object { Write-Output ("  " + $_) }
$e2 = [WX3]::Anchor(4)
Write-Output ("anchor now: flags=" + $e2.flags + " armedAt=" + $e2.armedAtMs + " rect=" + $e2.left + "," + $e2.top + "-" + $e2.right + "," + $e2.bottom)
$expectedX = $e2.left
$expectedY = $e2.bottom + 8
Write-Output ("expected (if it works): left ~" + $expectedX + ", top ~" + $expectedY)
if (-not $KeepOpen) { Esc; Start-Sleep -Milliseconds 500 }
