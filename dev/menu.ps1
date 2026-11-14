param([int]$X = 470, [int]$Y = 235, [string]$Out = 'menu.png')
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
'@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 500
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)   # RIGHTDOWN
Start-Sleep -Milliseconds 120
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)   # RIGHTUP
Start-Sleep -Milliseconds 700
$bmp = New-Object System.Drawing.Bitmap 520, 420
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X - 20, $Y - 20, 0, 0, (New-Object System.Drawing.Size 520, 420))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
# close the menu
[W.U]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero)
[W.U]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero)
Write-Output "menu captured -> $Out"
