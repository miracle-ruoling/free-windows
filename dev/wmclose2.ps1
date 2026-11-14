param([long]$Popup = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
"@
[void][W.U]::SetProcessDPIAware()
$p = [IntPtr]$Popup
$ok = [W.U]::PostMessage($p, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Write-Output ("WM_CLOSE posted ok={0} err={1}" -f $ok, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
Start-Sleep -Milliseconds 1200
$r = New-Object W.U+RECT
$exists = [W.U]::GetWindowRect($p, [ref]$r)
Write-Output ("exists={0} rect={1},{2}-{3},{4}" -f $exists, $r.Left, $r.Top, $r.Right, $r.Bottom)
