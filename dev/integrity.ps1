param([string]$Name = "dock")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Tok {
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, uint acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr tok, int cls, IntPtr buf, int len, out int ret);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    public static string Level(int pid) {
        IntPtr ph = OpenProcess(0x0400, false, pid);
        if (ph == IntPtr.Zero) return "open failed";
        IntPtr tok;
        if (!OpenProcessToken(ph, 0x0008, out tok)) { CloseHandle(ph); return "token failed"; }
        IntPtr buf = Marshal.AllocHGlobal(256);
        int ret;
        bool ok = GetTokenInformation(tok, 25 /*TokenIntegrityLevel*/, buf, 256, out ret);
        string res = "query failed";
        if (ok) {
            IntPtr sid = Marshal.ReadIntPtr(buf);
            int count = Marshal.ReadByte(IntPtr.Add(sid, 1));
            int sub = Marshal.ReadInt32(IntPtr.Add(sid, 8 + 4 * (count - 1)));
            res = sub.ToString("X") + (sub >= 0x3000 ? " (high)" : sub >= 0x2000 ? " (medium)" : sub >= 0x1000 ? " (low)" : " (untrusted)");
        }
        Marshal.FreeHGlobal(buf);
        CloseHandle(tok);
        CloseHandle(ph);
        return res;
    }
}
"@
foreach ($p in (Get-Process $Name -ErrorAction SilentlyContinue)) {
    "{0} pid={1} integrity={2}" -f $p.ProcessName, $p.Id, [Tok]::Level($p.Id)
}
