param([int]$X = 0, [int]$Y = 0, [string]$Out = 'shot_hover.png',
      [int]$CX = 900, [int]$CY = 260, [int]$CWD = 560, [int]$CHT = 520)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
'@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 700
$bmp = New-Object System.Drawing.Bitmap $CWD, $CHT
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($CX, $CY, 0, 0, (New-Object System.Drawing.Size $CWD, $CHT))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("hovered " + $X + "," + $Y + " capture " + $CX + "," + $CY + " " + $CWD + "x" + $CHT + " -> $Out")
