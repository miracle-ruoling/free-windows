Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string s);
'@

$pids = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
Write-Output ("qq pids: " + ($pids -join ', '))
$wmTaskbarCreated = [W.U]::RegisterWindowMessage('TaskbarCreated')
Write-Output ("TaskbarCreated msg = 0x{0:X}" -f $wmTaskbarCreated)

$script:rows = New-Object System.Collections.Generic.List[string]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $wp = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
    if ($script:pids -notcontains $wp) { return $true }
    $sb = New-Object System.Text.StringBuilder 200
    [void][W.U]::GetWindowText($h, $sb, 200)
    $cl = New-Object System.Text.StringBuilder 120
    [void][W.U]::GetClassName($h, $cl, 120)
    $ex = [W.U]::GetWindowLong($h, -16)
    $script:rows.Add(("hwnd={0} pid={1} vis={2} class={3} style=0x{4:X} title='{5}'" -f $h, $wp, [W.U]::IsWindowVisible($h), $cl.ToString(), $ex, $sb.ToString()))
    return $true
}
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
$script:rows | ForEach-Object { Write-Output $_ }
Write-Output ('total ' + $script:rows.Count)
