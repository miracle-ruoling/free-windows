Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
"@
$host0 = [IntPtr]0x10B34
$main = [IntPtr]68356
Write-Output ("main visible = " + [W.U]::IsWindowVisible($main))
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($main, [ref]$r)
Write-Output ("main rect = " + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
$ok = [W.U]::SetForegroundWindow($main)
Write-Output ("SetForegroundWindow -> " + $ok)
[void][W.U]::SetCursorPos(1200, 400)
Start-Sleep -Milliseconds 400
[void][W.U]::PostMessage($host0, 0x8001, [IntPtr]3, [IntPtr]0x0204)
Start-Sleep -Milliseconds 130
[void][W.U]::PostMessage($host0, 0x8001, [IntPtr]3, [IntPtr]0x0205)
Start-Sleep -Milliseconds 1600
Write-Output "posted right click"
