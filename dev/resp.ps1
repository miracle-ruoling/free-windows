param([int]$ProcId = 22676)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr res);
[DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
'@
$script:rows = New-Object System.Collections.Generic.List[string]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $wp = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
    if ($wp -ne $script:target) { return $true }
    $res = [IntPtr]::Zero
    $t0 = Get-Date
    $ok = [W.U]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 800, [ref]$res)
    $ms = ((Get-Date) - $t0).TotalMilliseconds
    $script:rows.Add(("hwnd={0} vis={1} hung={2} ping={3} took={4:N0}ms" -f $h, [W.U]::IsWindowVisible($h), [W.U]::IsHungAppWindow($h), $ok, $ms))
    return $true
}
$script:target = $ProcId
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
$script:rows | ForEach-Object { Write-Output $_ }
