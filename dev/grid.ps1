param([string]$Out = 'shot_grid.png', [int]$DxFromRight = 32)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
[void][W.U]::SetProcessDPIAware()
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
if ($h -eq [IntPtr]::Zero) { Write-Output 'no strip window'; exit 1 }
$c = New-Object W.U+RECT
[void][W.U]::GetClientRect($h, [ref]$c)
$x = $c.Right - $DxFromRight
$y = [int]($c.Bottom / 2)
$p = New-Object W.U+POINT
$p.X = $x; $p.Y = $y
[void][W.U]::ClientToScreen($h, [ref]$p)
[void][W.U]::SetCursorPos($p.X, $p.Y)
Start-Sleep -Milliseconds 900
$lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
[void][W.U]::SendMessage($h, 0x0201, [IntPtr]1, $lp)      # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 60
[void][W.U]::SendMessage($h, 0x0202, [IntPtr]0, $lp)      # WM_LBUTTONUP
Start-Sleep -Milliseconds 700
$sw = [W.U]::GetSystemMetrics(0)
$sh = [W.U]::GetSystemMetrics(1)
$bmp = New-Object System.Drawing.Bitmap $sw, $sh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $sw, $sh))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("clicked client " + $x + "," + $y + " screen " + $p.X + "," + $p.Y + " -> $Out")
