# §3.43 soak: 贴边隐藏 藏/醒 N 轮，两个成员必须始终对齐（条 = 基准，托盘相对它不动）。
# 顺带在最苛刻的时机插两件事：藏起来时重载配置（设置面板应用会走这条路），
# 以及在隐形条上按一下成员边框（用户会话里出现过 tray bar: resize start edge=9）。
# 参数用 $args 取（脚本以 -File 调用时 param 绑定会被前面的注释块搅乱，不必冒险）
$Rounds = 6
if ($args.Count -ge 1) { $Rounds = [int]$args[0] }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices;
public class G {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  public static IntPtr H(string cls, string title) { return FindWindow(cls, title); }
  public static RC Rect(IntPtr h) { RC r; GetWindowRect(h, out r); return r; }
  public static void Reload(IntPtr h) { SendMessage(h, 0x0113, (IntPtr)2, (IntPtr)0); }  // WM_TIMER 2
  public static void Press(IntPtr h, int x, int y) {                                     // down+up, no move
    IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
    SendMessage(h, 0x0201, (IntPtr)1, lp);
    System.Threading.Thread.Sleep(60);
    SendMessage(h, 0x0202, (IntPtr)0, lp);
  }
}
"@
$strip = [G]::H("DockStripWindow", "dock")
$tray = [G]::H("DockTrayBarWindow", "dock tray bar")
if ($strip -eq [IntPtr]::Zero -or $tray -eq [IntPtr]::Zero) { Write-Output 'windows not found'; exit 1 }

$awakeY = [G]::Rect($strip).T
$s0 = [G]::Rect($strip); $t0 = [G]::Rect($tray)
$offY = $t0.T - $s0.T
Write-Output ("reference: strip y={0} tray y={1} (tray offset {2})" -f $s0.T, $t0.T, $offY)

$fail = 0
for ($n = 1; $n -le $Rounds; $n++) {
  [void][S]::SetCursorPos(700, 600)          # leave -> hide
  Start-Sleep -Milliseconds 1200
  if ($n % 3 -eq 0) { [G]::Reload($strip); Start-Sleep -Milliseconds 900 }        # settings apply
  if ($n % 2 -eq 0) { [G]::Press($tray, 2, 40); Start-Sleep -Milliseconds 500 }   # invisible member edge
  $sh = [G]::Rect($strip); $th = [G]::Rect($tray)
  $hidOff = ($th.T - $sh.T) - $offY
  [void][S]::SetCursorPos(800, 2)            # into the band -> wake
  Start-Sleep -Milliseconds 1300
  $sw = [G]::Rect($strip); $tw = [G]::Rect($tray)
  $wakeOff = ($tw.T - $sw.T) - $offY
  $ok = ($hidOff -eq 0) -and ($wakeOff -eq 0) -and ($sw.T -eq $awakeY)
  if (-not $ok) { $fail++ }
  Write-Output ("round {0}: hidden strip={1},tray={2} (off {3})   awake strip={4},tray={5} (off {6})  {7}" -f `
      $n, $sh.T, $th.T, $hidOff, $sw.T, $tw.T, $wakeOff, $(if ($ok) { 'PASS' } else { 'FAIL' }))
}
Write-Output ("`n$($Rounds - $fail)/$Rounds rounds kept the members aligned")
if ($fail) { (Get-LogLines | Select-Object -Last 40 | Where-Object { $_ -match 'slide track|parked slot' }) -join "`n" }
