# Dump Local\DockTaskbarCtl_v1 (cloak / allow / deny deadlines) and watch it for changes.
#   -Watch N   poll for N ms, print every change
param([int]$Watch = 0)
Add-Type -Language CSharp @"
using System; using System.Diagnostics; using System.IO.MemoryMappedFiles; using System.Runtime.InteropServices; using System.Threading;
public class TC {
  [StructLayout(LayoutKind.Sequential)]
  public struct Blk {
    public uint magic; public uint version; public uint cloakUntilMs; public uint pad;
    public uint extMagic; public uint extVersion; public uint allowUntilMs; public uint denyUntilMs;
  }
  static string U(uint v) { uint now = (uint)Environment.TickCount; return v == 0 ? "0" : v + " (" + (int)(v - now) + " ms)"; }
  public static string Read() {
    try {
      using (var mm = MemoryMappedFile.OpenExisting(@"Local\DockTaskbarCtl_v1", MemoryMappedFileRights.Read)) {
        using (var acc = mm.CreateViewAccessor(0, Marshal.SizeOf(typeof(Blk)), MemoryMappedFileAccess.Read)) {
          Blk b; acc.Read(0, out b);
          return string.Format("magic=0x{0:X8} ver={1} cloak={2} | ext=0x{3:X8}/{4} allow={5} deny={6}",
              b.magic, b.version, U(b.cloakUntilMs), b.extMagic, b.extVersion, U(b.allowUntilMs), U(b.denyUntilMs));
        }
      }
    } catch (Exception e) { return "block not available: " + e.GetType().Name; }
  }
}
"@
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ($Watch -le 0) { [TC]::Read(); exit 0 }
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = ""
while ($sw.ElapsedMilliseconds -lt $Watch) {
    $cur = [TC]::Read()
    if ($cur -ne $last) { Write-Output ("{0,6} ms  {1}" -f $sw.ElapsedMilliseconds, $cur); $last = $cur }
    Start-Sleep -Milliseconds 10
}
