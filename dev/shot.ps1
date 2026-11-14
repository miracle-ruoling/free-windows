param([int]$X = 260, [int]$Y = 50, [int]$W = 1500, [int]$H = 170, [string]$Out = 'shot.png')
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Namespace W -Name D -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][W.D]::SetProcessDPIAware()
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
$g.Dispose()
$full = Join-Path (Resolve-Path -LiteralPath '.').Path $Out
$bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output $full
