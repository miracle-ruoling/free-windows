
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
"@
$h = [IntPtr]3607338
[void][W.U]::SetCursorPos(400, 900)
Start-Sleep -Milliseconds 200
[void][W.U]::PostMessage($h, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_ACTIVATE WA_INACTIVE
[void][W.U]::PostMessage($h, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_KILLFOCUS
Start-Sleep -Milliseconds 800
Write-Output done
