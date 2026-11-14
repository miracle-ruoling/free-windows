param([switch]$Move)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string win);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
[void][W.U]::SetProcessDPIAware()
$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'dock not running'; exit }
$h = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($h, [ref]$r)
Write-Output ("strip=" + $h + " rect=" + $r.Left + "," + $r.Top + " " + ($r.Right - $r.Left) + "x" + ($r.Bottom - $r.Top))
$c = New-Object W.U+POINT
[void][W.U]::GetCursorPos([ref]$c)
Write-Output ("cursor=" + $c.X + "," + $c.Y)
if ($Move) {
    # a spot in the middle of the strip but off the icons is impossible; use the
    # right end of the pill so no tooltip pops up
    $cx = $r.Right - 60
    $cy = [int](($r.Top + $r.Bottom) / 2)
    [void][W.U]::SetCursorPos($cx, $cy)
    Write-Output ("moved cursor to " + $cx + "," + $cy)
}
