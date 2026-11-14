param([string]$Set = '', [string]$Out = 'shot_one.png')
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
if ($Set -ne '') { & powershell -NoProfile -ExecutionPolicy Bypass -File "$here\setcfg.ps1" -Set $Set | Out-Null }
Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400
Start-Process "$dockDir\dock.exe"
Start-Sleep -Milliseconds 1600
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
$rc = New-Object W.U+RECT
[void][W.U]::GetWindowRect($h, [ref]$rc)
[void][W.U]::SetCursorPos(($rc.Right - 55), [int](($rc.Top + $rc.Bottom) / 2))
Start-Sleep -Milliseconds 500
# capture the strip plus a margin, so the panel edge is in frame
$pad = 24
$cx = $rc.Left - $pad
$cy = $rc.Top - $pad
$cw = ($rc.Right - $rc.Left) + $pad * 2
$ch = ($rc.Bottom - $rc.Top) + $pad * 2
$bmp = New-Object System.Drawing.Bitmap $cw, $ch
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($cx, $cy, 0, 0, (New-Object System.Drawing.Size $cw, $ch))
$g.Dispose()
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("saved $Out  strip=" + $rc.Left + "," + $rc.Top + " " + ($rc.Right - $rc.Left) + "x" + ($rc.Bottom - $rc.Top))
