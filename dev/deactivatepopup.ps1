Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
'@
$owner = [IntPtr]0x106CE    # WPFTaskbarIcon window
$popup = [IntPtr]4524716
foreach ($h in @($owner, $popup)) {
    [void][W.U]::PostMessage($h, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_ACTIVATE inactive
    [void][W.U]::PostMessage($h, 0x001C, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_ACTIVATEAPP false
    [void][W.U]::PostMessage($h, 0x0086, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_NCACTIVATE false
}
Start-Sleep -Milliseconds 400
$fg = [W.U]::GetForegroundWindow()
Write-Output ("foreground = " + $fg)
[void][W.U]::SetForegroundWindow($fg)   # re-assert the user's window as foreground
Start-Sleep -Milliseconds 700
Write-Output ("popup visible = " + [W.U]::IsWindowVisible($popup))
