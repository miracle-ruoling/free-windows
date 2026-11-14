
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
"@
$h = [IntPtr]3607338
[void][W.U]::SetCursorPos(600, 700)
Start-Sleep -Milliseconds 300
[void][W.U]::PostMessage($h, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)
[void][W.U]::PostMessage($h, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero)
[void][W.U]::PostMessage($h, 0x0101, [IntPtr]0x1B, [IntPtr]0xC0000001)
Start-Sleep -Milliseconds 600
Write-Output done
