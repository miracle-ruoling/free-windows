param([long]$Hwnd = 0x106CE, [int]$Uid = 0, [int]$Msg = 0x400, [string]$Proc = 'LZTray',
      [string]$Steps = 'down', [int]$MenuHwnd = 4524716)
# Single-shot: dismiss whatever is open, post one message sequence, report whether
# the app's popup is visible. Steps: down | up | downup | none
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
[void][W.U]::SetProcessDPIAware()
$target = [IntPtr]$Hwnd
$menu = [IntPtr]$MenuHwnd

# dismiss by stealing focus: the popup is non-activating, so blur it
[void][W.U]::SetCursorPos(300, 800)
[void][W.U]::PostMessage($menu, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CANCELMODE
[void][W.U]::PostMessage($menu, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_ACTIVATE inactive
[void][W.U]::PostMessage($menu, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_KILLFOCUS
Start-Sleep -Milliseconds 900
$state0 = [W.U]::IsWindowVisible($menu)
Write-Output ("after dismiss: visible=" + $state0)

[void][W.U]::SetCursorPos(900, 300)
Start-Sleep -Milliseconds 200
switch ($Steps) {
    'down'   { [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204) }
    'up'     { [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205) }
    'downup' { [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
               Start-Sleep -Milliseconds 90
               [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205) }
    'none'   { }
}
Start-Sleep -Milliseconds 1100
Write-Output ("steps={0} -> visible={1}" -f $Steps, [W.U]::IsWindowVisible($menu))
