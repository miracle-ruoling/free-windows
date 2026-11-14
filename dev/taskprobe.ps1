Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
'@

$rows = New-Object System.Collections.Generic.List[string]
$names = @('WorkBuddy', 'WorkBuddyManager', 'GameViewer', 'uu')
foreach ($n in $names) {
    $ps = Get-Process $n -ErrorAction SilentlyContinue
    if (-not $ps) { $rows.Add('--- ' + $n + ': not running'); continue }
    foreach ($p in $ps) {
        $procId = $p.Id
        $rows.Add('--- ' + $n + ' pid=' + $procId)
        $cb = [W.U+EnumProc]{
            param($h, $l)
            $wpid = [uint32]0
            [void][W.U]::GetWindowThreadProcessId($h, [ref]$wpid)
            if ($wpid -ne $procId) { return $true }
            $sb = New-Object System.Text.StringBuilder 256
            [void][W.U]::GetWindowText($h, $sb, 256)
            $cl = New-Object System.Text.StringBuilder 128
            [void][W.U]::GetClassName($h, $cl, 128)
            $ex = [W.U]::GetWindowLong($h, -20)
            $owner = [W.U]::GetWindow($h, 4)
            $flags = ''
            if ($ex -band 0x80) { $flags += 'TOOLWINDOW ' }
            if ($ex -band 0x40000) { $flags += 'APPWINDOW ' }
            if ($ex -band 0x8000000) { $flags += 'NOACTIVATE ' }
            $script:rows.Add('    vis=' + [W.U]::IsWindowVisible($h) + ' iconic=' + [W.U]::IsIconic($h) + ' owner=' + $owner + ' ex=[' + $flags + '] class=' + $cl.ToString() + ' title=' + $sb.ToString())
            return $true
        }
        [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    }
}
$rows | ForEach-Object { Write-Output $_ }
