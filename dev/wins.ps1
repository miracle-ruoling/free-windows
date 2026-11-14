Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
$procs = @(Get-Process dock -ErrorAction SilentlyContinue)
Write-Output ("dock processes: " + $procs.Count)
foreach ($p in $procs) { Write-Output ("  pid=" + $p.Id + " start=" + $p.StartTime) }
$rows = New-Object System.Collections.Generic.List[object]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $pid2 = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($procs -and ($pid2 -eq $procs[0].Id -or ($procs.Count -gt 1 -and $pid2 -eq $procs[1].Id))) {
        $cls = New-Object System.Text.StringBuilder 128
        [void][W.U]::GetClassName($h, $cls, 128)
        $tx = New-Object System.Text.StringBuilder 128
        [void][W.U]::GetWindowText($h, $tx, 128)
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $rows.Add(("  " + $cls.ToString() + " '" + $tx.ToString() + "' vis=" + [W.U]::IsWindowVisible($h) + " " + $r.Left + "," + $r.Top + " " + ($r.Right - $r.Left) + "x" + ($r.Bottom - $r.Top)))
    }
    return $true
}
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
$rows | ForEach-Object { Write-Output $_ }
