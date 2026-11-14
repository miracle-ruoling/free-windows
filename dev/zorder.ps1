Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
$h = [W.U]::GetTopWindow([IntPtr]::Zero)
$i = 0
while ($h -ne [IntPtr]::Zero -and $i -lt 14) {
    $cls = New-Object System.Text.StringBuilder 128
    [void][W.U]::GetClassName($h, $cls, 128)
    $tx = New-Object System.Text.StringBuilder 128
    [void][W.U]::GetWindowText($h, $tx, 128)
    $r = New-Object W.U+RECT
    [void][W.U]::GetWindowRect($h, [ref]$r)
    $ex = [W.U]::GetWindowLong($h, -20)
    $topmost = ($ex -band 0x8) -ne 0
    $tool = ($ex -band 0x80) -ne 0
    Write-Output ("{0,2} {1,-38} top={2,-5} tool={3,-5} vis={4,-5} {5},{6} {7}x{8} '{9}'" -f $i, $cls.ToString(), $topmost, $tool, [W.U]::IsWindowVisible($h), $r.Left, $r.Top, ($r.Right-$r.Left), ($r.Bottom-$r.Top), $tx.ToString())
    $h = [W.U]::GetWindow($h, 2)
    $i++
}
