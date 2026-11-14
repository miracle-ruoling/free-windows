param([int]$X = 16, [int]$Y = 16, [switch]$Move)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
[void][W.U]::SetProcessDPIAware()
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
if ($h -eq [IntPtr]::Zero) { Write-Output 'no strip'; exit 1 }
$p = New-Object W.U+POINT
$p.X = $X; $p.Y = $Y
[void][W.U]::ClientToScreen($h, [ref]$p)
if ($Move) { [void][W.U]::SetCursorPos($p.X, $p.Y); Start-Sleep -Milliseconds 300 }
$lp = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
[void][W.U]::SendMessage($h, 0x0201, [IntPtr]1, $lp)
Start-Sleep -Milliseconds 80
[void][W.U]::SendMessage($h, 0x0202, [IntPtr]0, $lp)
Write-Output ("posted click at client " + $X + "," + $Y + " (screen " + $p.X + "," + $p.Y + ")")
