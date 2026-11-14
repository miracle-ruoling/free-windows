param([int]$X = 960, [int]$Y = 60)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
$p = New-Object W.U+POINT
$p.X = $X; $p.Y = $Y
$h = [W.U]::WindowFromPoint($p)
$root = [W.U]::GetAncestor($h, 2)
foreach ($w in @($h, $root)) {
    if ($w -eq [IntPtr]::Zero) { continue }
    $procId = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($w, [ref]$procId)
    $cl = New-Object System.Text.StringBuilder 120
    [void][W.U]::GetClassName($w, $cl, 120)
    $tx = New-Object System.Text.StringBuilder 200
    [void][W.U]::GetWindowText($w, $tx, 200)
    $r = New-Object W.U+RECT
    [void][W.U]::GetWindowRect($w, [ref]$r)
    $pn = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
    Write-Output ("hwnd={0} pid={1}({2}) class={3} rect={4},{5}-{6},{7} title='{8}'" -f $w, $procId, $pn, $cl.ToString(), $r.Left, $r.Top, $r.Right, $r.Bottom, $tx.ToString())
}
