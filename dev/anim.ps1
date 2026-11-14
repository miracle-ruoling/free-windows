param([int]$X = 700, [int]$Y = 231, [int]$CX = 540, [int]$CY = 150, [int]$W = 500, [int]$H = 170)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
'@
[void][W.U]::SetProcessDPIAware()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# park far away first so the animation starts from rest
[void][W.U]::SetCursorPos(20, 1000)
Start-Sleep -Milliseconds 700
[void][W.U]::SetCursorPos($X, $Y)
$delays = @(90, 90, 90, 400)
$i = 0
foreach ($d in $delays) {
    Start-Sleep -Milliseconds $d
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($CX, $CY, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
    $bmp.Save("$here\anim$i.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $i++
}
Write-Output ("frames: " + $i)
