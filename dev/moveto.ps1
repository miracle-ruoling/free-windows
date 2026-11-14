param([int]$X = 300, [int]$Y = 700, [string]$Out = '', [int]$CX = 0, [int]$CY = 0,
      [int]$W = 0, [int]$H = 0)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
[void][W.U]::SetProcessDPIAware()
Write-Output ("screen: " + [W.U]::GetSystemMetrics(0) + "x" + [W.U]::GetSystemMetrics(1))
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 120
$p = New-Object W.U+POINT
[void][W.U]::GetCursorPos([ref]$p)
Write-Output ("cursor now: " + $p.X + "," + $p.Y + " (asked " + $X + "," + $Y + ")")
if ($Out -ne '' -and $W -gt 0 -and $H -gt 0) {
    Start-Sleep -Milliseconds 900
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($CX, $CY, 0, 0, (New-Object System.Drawing.Size $W, $H))
    $g.Dispose()
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("saved $Out")
}
