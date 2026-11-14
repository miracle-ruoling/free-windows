param([long]$Hwnd = 0x106CE, [int]$Uid = 0, [int]$Msg = 0x400)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
'@
$h = [IntPtr]$Hwnd
$ownerPid = [uint32]0
[void][W.U]::GetWindowThreadProcessId($h, [ref]$ownerPid)
$up = [W.U]::PostMessage($h, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Write-Output ("PostMessage(UP) to 0x{0:X} (pid {1}) -> ok={2} err={3}" -f $Hwnd, $ownerPid, $up, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
$dn = [W.U]::PostMessage($h, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
Write-Output ("PostMessage(DOWN) -> ok={0} err={1}" -f $dn, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
