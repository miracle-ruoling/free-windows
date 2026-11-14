param([int]$X = 1186, [int]$Y = 223, [long]$Hwnd = 0x10A72, [int]$Uid = 3, [int]$Msg = 0x8001, [int]$Demote = 1)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
"@
[void][W.U]::SetProcessDPIAware()
$panel = [W.U]::FindWindow("DockGridWindow", $null)
Write-Output ("panel = " + $panel)
if ($Demote -eq 1 -and $panel -ne [IntPtr]::Zero) {
    # HWND_NOTOPMOST == (HWND)-2
    [void][W.U]::SetWindowPos($panel, [IntPtr](-2), 0, 0, 0, 0, 0x0013)  # NOMOVE|NOSIZE|NOACTIVATE|NOOWNERZORDER?
    Write-Output "demoted panel"
}
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 250
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
Start-Sleep -Milliseconds 90
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Write-Output "posted"
