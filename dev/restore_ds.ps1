Add-Type -Namespace Z2 -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$h = [IntPtr]68212
Write-Output ("before: visible=" + [Z2.W]::IsWindowVisible($h) + " iconic=" + [Z2.W]::IsIconic($h))
[void][Z2.W]::ShowWindow($h, 9)     # SW_RESTORE
Start-Sleep -Milliseconds 200
[void][Z2.W]::ShowWindow($h, 3)     # SW_SHOWMAXIMIZED
Start-Sleep -Milliseconds 200
[void][Z2.W]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300
$r = New-Object Z2.W+RECT
[void][Z2.W]::GetWindowRect($h, [ref]$r)
Write-Output ("after: visible=" + [Z2.W]::IsWindowVisible($h) + " iconic=" + [Z2.W]::IsIconic($h) + " rect=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
