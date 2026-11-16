# Why do some tray icons ignore the click we forward? This probe posts the same callback
# message to the app's tray window in three different shapes and reports what the app did.
#
#   -Mode v0    wParam = icon id,      lParam = message        (what dock.exe sends today)
#   -Mode v4    wParam = MAKELPARAM(x,y), lParam = MAKELPARAM(message, icon id)
#                                                              (NOTIFYICON_VERSION_4 layout)
#   -Mode dbl   down, up, WM_LBUTTONDBLCLK, up  (what a real double click delivers; apps that
#               only implement "double click" listen for WM_LBUTTONDBLCLK, which posted
#               messages never produce by themselves)
#
# Observation: the visible top-level windows of that exe's processes and the foreground window
# before/after. Usage:
#   dev\t_traypost.ps1 -Exe windhawk.exe -Mode v4
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [ValidateSet("v0", "v4", "dbl")][string]$Mode = "v0",
    [int]$GapMs = 70
)
Add-Type -Language CSharp @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public class TP {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint hi, uint lo, UIntPtr bytes);
  [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public delegate bool EnumProc(IntPtr h, IntPtr lp);

  [StructLayout(LayoutKind.Sequential)]
  public struct Entry {
    public ulong hwnd; public uint uid; public uint cbMsg; public uint isGuid; public uint pid;
    public Guid guid;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128, ArraySubType = UnmanagedType.U2)] public char[] tip;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 260, ArraySubType = UnmanagedType.U2)] public char[] exe;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct Shm {
    public uint magic; public uint version; public uint count; public uint capacity; public ulong updatedMs;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)] public Entry[] entries;
  }

  public static string Find(string exeNeedle) {
    IntPtr map = OpenFileMapping(0x0004, false, @"Local\DockTrayBridge_v1");
    if (map == IntPtr.Zero) return "ERR no tray bridge (is the tray-icons-bridge mod loaded?)";
    IntPtr view = MapViewOfFile(map, 0x0004, 0, 0, (UIntPtr)Marshal.SizeOf(typeof(Shm)));
    if (view == IntPtr.Zero) { CloseHandle(map); return "ERR map failed"; }
    Shm s = (Shm)Marshal.PtrToStructure(view, typeof(Shm));
    string result = "ERR not found";
    int n = (int)Math.Min(s.count, 128u);
    for (int i = 0; i < n; i++) {
      string exe = new string(s.entries[i].exe ?? new char[0]).TrimEnd('\0');
      string tip = new string(s.entries[i].tip ?? new char[0]).TrimEnd('\0');
      if (exe.IndexOf(exeNeedle, StringComparison.OrdinalIgnoreCase) >= 0 ||
          tip.IndexOf(exeNeedle, StringComparison.OrdinalIgnoreCase) >= 0) {
        Entry e = s.entries[i];
        result = "index=" + i + " hwnd=" + e.hwnd + " uid=" + e.uid + " cbMsg=0x" + e.cbMsg.ToString("X") +
                 " pid=" + e.pid + " tip='" + tip + "' exe='" + exe + "'";
        break;
      }
    }
    UnmapViewOfFile(view); CloseHandle(map);
    return result;
  }
  public static string Windows(uint pid) {
    List<string> l = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid || !IsWindowVisible(h) || IsIconic(h)) return true;
      StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
      if (b.ToString() == "tooltips_class32") return true;
      StringBuilder t = new StringBuilder(80); GetWindowText(h, t, 80);
      l.Add(b.ToString() + " '" + t + "'");
      return true; }, IntPtr.Zero);
    return l.Count == 0 ? "(no visible window)" : string.Join(" | ", l.ToArray());
  }
  public static string Fg() {
    IntPtr h = GetForegroundWindow();
    StringBuilder b = new StringBuilder(128); GetClassName(h, b, 128);
    StringBuilder t = new StringBuilder(80); GetWindowText(h, t, 80);
    return b.ToString() + " '" + t + "'";
  }
  public static int CursorX() { POINT p; GetCursorPos(out p); return p.X; }
  public static int CursorY() { POINT p; GetCursorPos(out p); return p.Y; }
}
'@

$info = [TP]::Find($Exe)
Write-Output ("entry: " + $info)
if ($info -like 'ERR*') { exit 1 }
[void]($info -match 'hwnd=(\d+) uid=(\d+) cbMsg=0x([0-9A-Fa-f]+) pid=(\d+)')
$hwnd = [IntPtr][int64]$Matches[1]
$uid = [int]$Matches[2]
$cb = [Convert]::ToUInt32($Matches[3], 16)
$procId = [uint32]$Matches[4]

Write-Output ("hwnd=" + $hwnd.ToInt64() + " isWindow=" + [TP]::IsWindow($hwnd) + " uid=$uid cbMsg=0x" + $cb.ToString("X") + " pid=$procId")
Write-Output ("before: fg=" + [TP]::Fg())
Write-Output ("        windows=" + [TP]::Windows($procId))

$DOWN = 0x0201; $UP = 0x0202; $DBL = 0x0203
function LP([int]$msg, [int]$id) { return [IntPtr]([int64](($id -shl 16) -bor ($msg -band 0xFFFF))) }
$x = [TP]::CursorX(); $y = [TP]::CursorY()

switch ($Mode) {
    'v0' {
        $w = [IntPtr]$uid
        Write-Output ("post DOWN wParam=$uid lParam=0x" + $DOWN.ToString("X")); [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$DOWN)
        Start-Sleep -Milliseconds $GapMs
        Write-Output ("post UP"); [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$UP)
    }
    'v4' {
        $w = [IntPtr]([int64]((($y -band 0xFFFF) -shl 16) -bor ($x -band 0xFFFF)))
        Write-Output ("post DOWN v4 wParam=$x,$y lParam=0x" + $DOWN.ToString("X") + "/id=$uid")
        [void][TP]::PostMessage($hwnd, $cb, $w, (LP $DOWN $uid))
        Start-Sleep -Milliseconds $GapMs
        Write-Output ("post UP v4"); [void][TP]::PostMessage($hwnd, $cb, $w, (LP $UP $uid))
    }
    'dbl' {
        $w = [IntPtr]$uid
        Write-Output "post DOWN / UP / DBLCLK / UP (real double click sequence)"
        [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$DOWN)
        Start-Sleep -Milliseconds $GapMs
        [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$UP)
        Start-Sleep -Milliseconds $GapMs
        [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$DBL)
        Start-Sleep -Milliseconds $GapMs
        [void][TP]::PostMessage($hwnd, $cb, $w, [IntPtr]$UP)
    }
}
Start-Sleep -Milliseconds 1200
Write-Output ("after : fg=" + [TP]::Fg())
Write-Output ("        windows=" + [TP]::Windows($procId))
