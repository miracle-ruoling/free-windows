param([long]$MenuHwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
'@
$m = [IntPtr]$MenuHwnd
Write-Output ("visible before: " + [W.U]::IsWindowVisible($m))
[void][W.U]::SetCursorPos(300, 800)
[void][W.U]::PostMessage($m, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_CANCELMODE
[void][W.U]::PostMessage($m, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero)    # ESC down
[void][W.U]::PostMessage($m, 0x0101, [IntPtr]0x1B, [IntPtr]0xC0000001) # ESC up
[void][W.U]::PostMessage($m, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_ACTIVATE inactive
[void][W.U]::PostMessage($m, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_KILLFOCUS
Start-Sleep -Milliseconds 900
Write-Output ("visible after posts: " + [W.U]::IsWindowVisible($m))
if ([W.U]::IsWindowVisible($m)) {
    # last resort for a stuck popup: hide it directly (it is a display-only window)
    [void][W.U]::ShowWindow($m, 0)
    Start-Sleep -Milliseconds 300
    Write-Output ("visible after ShowWindow(SW_HIDE): " + [W.U]::IsWindowVisible($m))
}
