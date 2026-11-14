Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
"@
$host0 = [IntPtr]0x10B34
$main = [IntPtr]68356
$fg = [W.U]::GetForegroundWindow()
$fgThread = [W.U]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
$my = [W.U]::GetCurrentThreadId()
Write-Output ("fg=" + $fg + " fgThread=" + $fgThread + " my=" + $my)
[void][W.U]::AttachThreadInput($my, $fgThread, $true)
$ok = [W.U]::SetForegroundWindow($main)
[void][W.U]::AttachThreadInput($my, $fgThread, $false)
Write-Output ("forced SetForegroundWindow -> " + $ok + " now fg=" + [W.U]::GetForegroundWindow())
[void][W.U]::SetCursorPos(1200, 400)
Start-Sleep -Milliseconds 400
[void][W.U]::PostMessage($host0, 0x8001, [IntPtr]3, [IntPtr]0x0204)
Start-Sleep -Milliseconds 130
[void][W.U]::PostMessage($host0, 0x8001, [IntPtr]3, [IntPtr]0x0205)
Start-Sleep -Milliseconds 1600
Write-Output "posted"
