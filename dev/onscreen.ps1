param([int]$ProcId = 36036)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
"@
[void][W.U]::SetProcessDPIAware()
$script:rows = New-Object System.Collections.Generic.List[string]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $wp = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
    if ($wp -ne $script:target) { return $true }
    if (-not [W.U]::IsWindowVisible($h)) { return $true }
    $r = New-Object W.U+RECT
    [void][W.U]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left
    $ht = $r.Bottom - $r.Top
    if ($w -le 0 -or $ht -le 0) { return $true }
    $hits = 0
    foreach ($fx in 0.25, 0.5, 0.75) {
        foreach ($fy in 0.2, 0.5, 0.8) {
            $pt = New-Object W.U+POINT
            $pt.X = [int]($r.Left + $w * $fx)
            $pt.Y = [int]($r.Top + $ht * $fy)
            $hit = [W.U]::WindowFromPoint($pt)
            if ($hit -eq [IntPtr]::Zero) { continue }
            if ($hit -eq $h -or [W.U]::GetAncestor($hit, 2) -eq $h) { $hits++ }
        }
    }
    $cl = New-Object System.Text.StringBuilder 80
    [void][W.U]::GetClassName($h, $cl, 80)
    $script:rows.Add(("hwnd={0} {1}x{2} at {3},{4} onscreen={5}/9 class={6}" -f $h, $w, $ht, $r.Left, $r.Top, $hits, $cl.ToString()))
    return $true
}
$script:target = $ProcId
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
$script:rows | ForEach-Object { Write-Output $_ }
