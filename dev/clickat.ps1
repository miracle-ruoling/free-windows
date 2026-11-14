param([int]$X = 1700, [int]$Y = 900, [string]$Button = 'left', [int]$Hold = 60)
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
public class C {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
[void][C]::SetProcessDPIAware()
$p = New-Object C+POINT
$ok = [C]::SetCursorPos($X, $Y)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
[void][C]::GetCursorPos([ref]$p)
Write-Output ("cursor {0},{1} (SetCursorPos ok={2} err={3})" -f $p.X,$p.Y,$ok,$err)
Start-Sleep -Milliseconds 150
$down = 0x0002; $up = 0x0004
if ($Button -eq 'right') { $down = 0x0008; $up = 0x0010 }
[C]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds $Hold
[C]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
Write-Output ("clicked " + $Button)
