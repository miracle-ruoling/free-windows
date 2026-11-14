Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
"@
$h = [IntPtr]0x10B34
[void][W.U]::SetCursorPos(1000, 300)
Start-Sleep -Milliseconds 300
[void][W.U]::PostMessage($h, 0x8001, [IntPtr]3, [IntPtr]0x0204)
Start-Sleep -Milliseconds 150
[void][W.U]::PostMessage($h, 0x8001, [IntPtr]3, [IntPtr]0x0205)
Start-Sleep -Milliseconds 1500
Write-Output "posted right click with window visible"
