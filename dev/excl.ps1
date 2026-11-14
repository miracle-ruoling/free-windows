param([int]$X = 540, [int]$Y = 270, [int]$W = 1320, [int]$H = 140)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr h, uint a);
'@
[void][W.U]::SetProcessDPIAware()
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
function Shot($name) {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
    $bmp.Save("$here\$name", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
Shot 'excl_off.png'
$ok = [W.U]::SetWindowDisplayAffinity($h, 0x11)   # WDA_EXCLUDEFROMCAPTURE
Start-Sleep -Milliseconds 150
Shot 'excl_on.png'
[void][W.U]::SetWindowDisplayAffinity($h, 0)
Write-Output ("excluded ok=" + $ok)
