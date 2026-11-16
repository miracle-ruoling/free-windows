# Open/close the "^" panel N times and report, for each attempt, whether the shell's own
# tray flyout opened (keyboard path via Win+B) or whether the dock had to fall back.
#   -Rounds 3   open+close cycles
param([int]$Rounds = 3, [int]$Wait = 4200)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Text;
public class TR {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr lp) {
      StringBuilder b = new StringBuilder(200); GetClassName(h, b, 200);
      if (b.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
    return found; }
  public static void Chev(IntPtr strip, int cx, int cy) {
    IntPtr lp = (IntPtr)(((long)cy << 16) | (uint)cx);
    PostMessage(strip, 0x0201, (IntPtr)1, lp); System.Threading.Thread.Sleep(60);
    PostMessage(strip, 0x0202, (IntPtr)0, lp); }
}
"@
[void][TR]::SetProcessDpiAwarenessContext([IntPtr](-4))
$log = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$strip = [TR]::Find("DockStripWindow"); $sr = New-Object TR+RECT
[void][TR]::GetWindowRect($strip, [ref]$sr)
$line = (Select-String -Path $log -Pattern "layout: " | Select-Object -Last 1).Line
$line -match "chevron=(-?\d+),(-?\d+)-(-?\d+),(-?\d+)" | Out-Null
$cx = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
$cy = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
Write-Output "chevron $cx,$cy"
$mark = (Get-Date).AddSeconds(-1)
for ($i = 1; $i -le $Rounds; $i++) {
    Write-Output ("--- round " + $i + " open  (" + (Get-Date).ToString("HH:mm:ss") + ")")
    [TR]::Chev($strip, $cx, $cy)
    Start-Sleep -Milliseconds $Wait
    Write-Output ("--- round " + $i + " close (" + (Get-Date).ToString("HH:mm:ss") + ")")
    [TR]::Chev($strip, $cx, $cy)
    Start-Sleep -Milliseconds $Wait
}
Write-Output "--- log ---"
Get-Content $log | Select-String -Pattern "native flyout (toggle|- |gone)|falling back|keyboard path" |
    Select-Object -Last (24) | ForEach-Object { $_.Line }
