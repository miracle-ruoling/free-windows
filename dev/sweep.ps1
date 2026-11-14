param([int[]]$Radii = @(0, 8, 16, 24, 32, 48, 64), [string]$Prefix = 'shot_r')
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string win);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dockDir = "$env:LOCALAPPDATA\Programs\Dock"
$ini = "$dockDir\dock.ini"
$exe = "$dockDir\dock.exe"

foreach ($r in $Radii) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$here\setcfg.ps1" -Set ("blurRadius=" + $r) | Out-Null
    Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 400
    Start-Process $exe
    Start-Sleep -Milliseconds 1500
    $h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
    if ($h -ne [IntPtr]::Zero) {
        $rc = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$rc)
        # park the cursor at the empty right end of the pill: keeps the strip
        # opaque without opening a thumbnail preview over the sample area
        [void][W.U]::SetCursorPos(($rc.Right - 55), [int](($rc.Top + $rc.Bottom) / 2))
        Start-Sleep -Milliseconds 400
        $bmp = New-Object System.Drawing.Bitmap 1670, 140
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen(0, 60, 0, 0, (New-Object System.Drawing.Size 1670, 140))
        $g.Dispose()
        $bmp.Save("$here\$Prefix$r.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Output ("r=" + $r + " strip=" + $rc.Left + "," + $rc.Top + " " + ($rc.Right - $rc.Left) + "x" + ($rc.Bottom - $rc.Top) + " -> $Prefix$r.png")
    } else {
        Write-Output ("r=" + $r + " strip window missing")
    }
}
