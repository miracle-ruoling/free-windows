Add-Type -Namespace W -Name K -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr tok);
[DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr tok, int cls, ref int buf, int len, out int ret);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
"@
$rows = New-Object System.Collections.Generic.List[string]
foreach ($p in Get-Process) {
    try {
        $h = [W.K]::OpenProcess(0x1000, $false, $p.Id)
        if ($h -eq [IntPtr]::Zero) { continue }
        $tok = [IntPtr]::Zero
        $elev = -1
        if ([W.K]::OpenProcessToken($h, 0x0008, [ref]$tok)) {
            $buf = 0
            $ret = 0
            if ([W.K]::GetTokenInformation($tok, 20, [ref]$buf, 4, [ref]$ret)) { $elev = $buf }
            [void][W.K]::CloseHandle($tok)
        }
        [void][W.K]::CloseHandle($h)
        if ($elev -eq 1) {
            $rows.Add(("{0,-6} {1}" -f $p.Id, $p.ProcessName))
        }
    } catch { }
}
Write-Output ("elevated processes: " + $rows.Count)
$rows | Sort-Object | ForEach-Object { Write-Output $_ }
