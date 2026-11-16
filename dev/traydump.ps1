# Print the live notification-area table that the Windhawk bridge mod publishes
# (Local\DockTrayBridge_v1) - the same list dock.exe turns into the grid cells, and in the
# same order (dock sorts it by tip). Layout must match windhawk/tray-icons-bridge.wh.cpp.
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class TrayDump {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint hi, uint lo, UIntPtr bytes);
  [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

  [StructLayout(LayoutKind.Sequential)]
  public struct Entry {
    public ulong hwnd;
    public uint uid;
    public uint cbMsg;
    public uint isGuid;
    public uint pid;
    public Guid guid;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128, ArraySubType = UnmanagedType.U2)] public char[] tip;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 260, ArraySubType = UnmanagedType.U2)] public char[] exe;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct Shm {
    public uint magic;
    public uint version;
    public uint count;
    public uint capacity;
    public ulong updatedMs;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)] public Entry[] entries;
  }

  public static string[] Dump() {
    IntPtr map = OpenFileMapping(0x0004, false, @"Local\DockTrayBridge_v1");
    if (map == IntPtr.Zero) return new string[] { "OpenFileMapping failed, err=" + Marshal.GetLastWin32Error() };
    int size = Marshal.SizeOf(typeof(Shm));
    IntPtr view = MapViewOfFile(map, 0x0004, 0, 0, (UIntPtr)size);
    if (view == IntPtr.Zero) { int e = Marshal.GetLastWin32Error(); CloseHandle(map); return new string[] { "MapViewOfFile failed, err=" + e }; }
    Shm s = (Shm)Marshal.PtrToStructure(view, typeof(Shm));
    string[] outLines = new string[(int)Math.Min(s.count, 128u) + 1];
    outLines[0] = string.Format("magic=0x{0:X8} version={1} count={2} capacity={3} sizeof(Shm)={4}",
      s.magic, s.version, s.count, s.capacity, size);
    int n = (int)Math.Min(s.count, 128u);
    for (int i = 0; i < n; i++) {
      Entry e = s.entries[i];
      string tip = new string(e.tip ?? new char[0]).TrimEnd('\0');
      string exe = new string(e.exe ?? new char[0]).TrimEnd('\0');
      outLines[i + 1] = string.Format("  [{0}] tip='{1}' exe='{2}' hwnd={3} uid={4} cbMsg=0x{5:X} pid={6}",
        i, tip, exe, e.hwnd, e.uid, e.cbMsg, e.pid);
    }
    UnmapViewOfFile(view);
    CloseHandle(map);
    return outLines;
  }
}
'@
Write-Output ("sizeof(Entry)=" + [System.Runtime.InteropServices.Marshal]::SizeOf([type]'TrayDump+Entry'))
foreach ($line in [TrayDump]::Dump()) { Write-Output $line }
