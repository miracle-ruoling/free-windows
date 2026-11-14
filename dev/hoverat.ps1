param([int]$X = 1204, [int]$Y = 30, [string]$Out = 'hoveritem.png', [int]$Wait = 400)
Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;
public class H {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
[void][H]::SetProcessDPIAware()
$ok = [H]::SetCursorPos($X, $Y)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
$p = New-Object H+POINT
[void][H]::GetCursorPos([ref]$p)
Write-Output ("SetCursorPos({0},{1}) ok={2} err={3} now={4},{5}" -f $X,$Y,$ok,$err,$p.X,$p.Y)
Start-Sleep -Milliseconds $Wait
Add-Type -AssemblyName System.Drawing
$w = 1920; $h = 1080
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save((Join-Path $here $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("saved " + $Out)
