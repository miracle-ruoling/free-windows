param([int]$X = 0, [int]$Y = 0, [string]$Out = 'rclick.png',
      [int]$CX = 0, [int]$CY = 0, [int]$W = 700, [int]$H = 500)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
'@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 500
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 110
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 800
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($CX, $CY, 0, 0, (New-Object System.Drawing.Size $W, $H))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("right-clicked " + $X + "," + $Y + " -> $Out")
