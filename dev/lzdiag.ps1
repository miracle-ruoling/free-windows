param([long]$Hwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$m = [IntPtr]$Hwnd
$ok = [W.U]::SetWindowPos($m, [IntPtr]::Zero, -3000, -3000, 0, 0, 0x0014)
Write-Output ("SetWindowPos ok={0} err={1}" -f $ok, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
$ok2 = [W.U]::PostMessage($m, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Write-Output ("PostMessage(WM_CLOSE) ok={0} err={1}" -f $ok2, [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
$p = Get-Process -Id 22676 -ErrorAction SilentlyContinue
if ($p) {
    $owner = (Get-CimInstance Win32_Process -Filter "ProcessId=22676").GetOwner()
    Write-Output ("LZTray path=" + $p.Path)
}
Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr tok);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr tok, int cls, IntPtr buf, int len, out int ret);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
$h = [W.K]::OpenProcess(0x1000, $false, 22676)   # PROCESS_QUERY_LIMITED_INFORMATION
Write-Output ("OpenProcess handle=" + $h)
if ($h -ne [IntPtr]::Zero) {
    $tok = [IntPtr]::Zero
    if ([W.K]::OpenProcessToken($h, 0x0008, [ref]$tok)) {
        $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(64)
        $ret = 0
        if ([W.K]::GetTokenInformation($tok, 18, $buf, 64, [ref]$ret)) {
            $sidPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($buf)
            $count = [System.Runtime.InteropServices.Marshal]::ReadByte($sidPtr, 1)
            $rid = [System.Runtime.InteropServices.Marshal]::ReadInt32($sidPtr, 8 + 4 * ($count - 1))
            Write-Output ("LZTray integrity = 0x{0:X}" -f $rid)
        }
        [void][W.K]::CloseHandle($tok)
    }
    [void][W.K]::CloseHandle($h)
}
