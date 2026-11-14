param([long]$Hwnd = 4524716, [int]$X = -3000, [int]$Y = -3000)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$m = [IntPtr]$Hwnd
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($m, [ref]$r)
Write-Output ("before: {0},{1}-{2},{3}" -f $r.Left, $r.Top, $r.Right, $r.Bottom)
# park the popup off screen: it refuses WM_CLOSE / WM_ACTIVATE / Esc / SW_HIDE,
# but it is a plain popup window so it can at least be moved out of the way
[void][W.U]::SetWindowPos($m, [IntPtr]::Zero, $X, $Y, 0, 0, 0x0004 -bor 0x0010)
Start-Sleep -Milliseconds 500
$r2 = New-Object W.U+RECT
[void][W.U]::GetWindowRect($m, [ref]$r2)
Write-Output ("after: {0},{1}-{2},{3} visible={4}" -f $r2.Left, $r2.Top, $r2.Right, $r2.Bottom, [W.U]::IsWindowVisible($m))
