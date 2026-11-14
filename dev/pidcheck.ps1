param([long]$A = 4524716, [long]$B = 0x106CE)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll", SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
"@
foreach ($pair in @(@('popup', $A), @('traywin', $B))) {
    $name = $pair[0]; $h = [IntPtr]$pair[1]
    $p = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$p)
    $ok = [W.U]::PostMessage($h, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)
    $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
    Write-Output ("{0}: hwnd={1} pid={2} name={3} postCancelMode={4} err={5}" -f $name, $h, $p, $proc.ProcessName, $ok, $err)
}
Write-Output ("current user: " + (whoami))
