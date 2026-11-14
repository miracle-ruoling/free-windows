param([int]$X = 1186, [int]$Y = 223, [long]$Hwnd = 0x10A72, [int]$Uid = 3, [int]$Msg = 0x8001)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
"@
[void][W.U]::SetProcessDPIAware()
[void][W.U]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 300
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
Start-Sleep -Milliseconds 90
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Write-Output "posted with cursor over the panel at $X,$Y"
