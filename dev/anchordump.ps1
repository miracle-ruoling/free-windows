# Read Local\DockAnchor_v1 and print what dock.exe published (the mod's view of it).
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

public class AnchorReader {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint hi, uint lo, UIntPtr bytes);
  [DllImport("kernel32.dll")]
  static extern bool UnmapViewOfFile(IntPtr p);
  [DllImport("kernel32.dll")]
  static extern bool CloseHandle(IntPtr h);

  [StructLayout(LayoutKind.Sequential)]
  public struct Entry {
    public uint kind;
    public uint flags;
    public int left, top, right, bottom;
    public int gapPx;
    public int pad0, pad1, pad2, pad3;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct Table {
    public uint magic;
    public uint version;
    public uint count;
    public uint updatedMs;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
    public Entry[] entries;
  }

  public static string Dump() {
    IntPtr map = OpenFileMapping(0x0004 /*FILE_MAP_READ*/, false, @"Local\DockAnchor_v1");
    if (map == IntPtr.Zero) {
      return "OpenFileMapping failed, err=" + Marshal.GetLastWin32Error() + " (is dock running?)";
    }
    IntPtr view = MapViewOfFile(map, 0x0004, 0, 0, (UIntPtr)Marshal.SizeOf(typeof(Table)));
    if (view == IntPtr.Zero) {
      int err = Marshal.GetLastWin32Error();
      CloseHandle(map);
      return "MapViewOfFile failed, err=" + err;
    }
    Table t = (Table)Marshal.PtrToStructure(view, typeof(Table));
    string s = string.Format("magic=0x{0:X8} ('{1}') version={2} count={3} updatedMs={4} sizeof(Table)={5}",
      t.magic, (char)(t.magic & 0xFF), t.version, t.count, t.updatedMs, Marshal.SizeOf(typeof(Table)));
    for (int i = 0; i < 16; i++) {
      Entry e = t.entries[i];
      if (e.kind == 0) continue;
      s += string.Format("\n  kind={0} rect={1},{2}-{3},{4} gap={5}", e.kind, e.left, e.top, e.right, e.bottom, e.gapPx);
    }
    UnmapViewOfFile(view);
    CloseHandle(map);
    return s;
  }
}
"@
Write-Output ([AnchorReader]::Dump())
