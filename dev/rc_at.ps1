param([int]$X = 1120, [int]$Y = 285, [string]$Out = 'rc.png', [int]$Wait = 1400)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
"@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 400
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 100
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $Wait
$w = [W.U]::GetSystemMetrics(0); $h = [W.U]::GetSystemMetrics(1)
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("right-clicked $X,$Y -> $Out")
