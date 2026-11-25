. .\dev\statelib.ps1
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class A2 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int ht, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static int Top() { IntPtr h = FindWindow("DockStripWindow", "dock"); RC r; GetWindowRect(h, out r); return r.T; }
}
"@
# 1) awake bar, click an icon -> audit must NOT fire (press delivered)
[void][S]::SetCursorPos(800, 2); Start-Sleep -Milliseconds 900
[void][S]::SetCursorPos(800, 76); Start-Sleep -Milliseconds 400
$before = (Get-LogLines).Count
[S]::LeftClick(); Start-Sleep -Milliseconds 600
Write-Output '--- normal click (expect LBUTTONDOWN, no audit) ---'
(Get-LogLines | Select-Object -Skip $before | Where-Object { $_ -ne '' -and $_ -match 'LBUTTONDOWN|press audit|click slot' }) -join "`n"
# 2) make the strip click-through by hand, then click -> audit must fire
$strip = [A2]::FindWindow("DockStripWindow", "dock")
$ex = 0x08080888L  # keep layered|topmost|toolwindow + add WS_EX_TRANSPARENT
[void][A2]::SetWindowPos($strip, [IntPtr]::Zero, 0,0,0,0, 0x0001 -bor 0x0002 -bor 0x0004 -bor 0x0010)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class EX2 {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  public static void MakeThrough(IntPtr h) { int ex = GetWindowLong(h, -20); SetWindowLong(h, -20, ex | 0x20); }
  public static string Ex(IntPtr h) { return "0x" + GetWindowLong(h, -20).ToString("X8"); }
}
"@
[EX2]::MakeThrough($strip)
Write-Output ("strip ex now " + [EX2]::Ex($strip))
$before2 = (Get-LogLines).Count
[S]::LeftClick(); Start-Sleep -Milliseconds 700
Write-Output '--- click while click-through (expect the audit) ---'
(Get-LogLines | Select-Object -Skip $before2 | Where-Object { $_ -ne '' -and $_ -match 'press audit|LBUTTONDOWN|press: left' }) -join "`n"
