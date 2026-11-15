# Minimal tooltip test in-process (PowerShell): create a tooltip, add a tool, report.
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

public class TtProbe {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr CreateWindowExW(uint exStyle, string cls, string name, uint style,
    int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, ref TOOLINFO ti);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr GetModuleHandleW(string name);

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct TOOLINFO {
    public int cbSize;
    public uint uFlags;
    public IntPtr hwnd;
    public IntPtr uId;
    public int left, top, right, bottom;
    public IntPtr hinst;
    public string lpszText;
    public IntPtr lParam;
  }

  const uint TTM_ADDTOOLW = 0x0400 + 50;

  public static string Run() {
    string cls = "tooltips_class32";
    IntPtr tip = CreateWindowExW(0x8 /*TOPMOST*/, cls, null,
      0x80000000 /*POPUP*/ | 0x01 /*ALWAYSTIP*/ | 0x02 /*NOPREFIX*/,
      0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, GetModuleHandleW(null), IntPtr.Zero);
    if (tip == IntPtr.Zero) return "CreateWindowEx failed, err=" + Marshal.GetLastWin32Error();

    TOOLINFO ti = new TOOLINFO();
    ti.cbSize = Marshal.SizeOf(typeof(TOOLINFO));
    ti.uFlags = 0x10 /*TTF_SUBCLASS*/;
    ti.hwnd = tip;                 // tool window = the tooltip itself, just to test the call
    ti.uId = (IntPtr)1;
    ti.left = 0; ti.top = 0; ti.right = 40; ti.bottom = 20;
    ti.lpszText = "hello";

    IntPtr r1 = SendMessageW(tip, TTM_ADDTOOLW, IntPtr.Zero, ref ti);
    return string.Format("sizeof={0} add={1} err={2}", ti.cbSize, r1.ToInt64(), Marshal.GetLastWin32Error());
  }
}
"@
Write-Output ([TtProbe]::Run())
