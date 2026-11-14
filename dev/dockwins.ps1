Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
Write-Output ("dock processes: " + @(Get-Process dock -ErrorAction SilentlyContinue).Count)
$script:rows = New-Object System.Collections.Generic.List[string]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 128
    [void][W.U]::GetClassName($h, $cls, 128)
    if ($cls.ToString() -like '*Dock*') {
        $p = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$p)
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $c = New-Object W.U+RECT
        [void][W.U]::GetClientRect($h, [ref]$c)
        $ex = [W.U]::GetWindowLong($h, -20)
        $script:rows.Add("  " + $cls.ToString() + " pid=" + $p + " hwnd=" + $h + " vis=" + [W.U]::IsWindowVisible($h) + " win=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top) + " client=" + $c.Right + "x" + $c.Bottom + " ex=0x" + $ex.ToString("X"))
    }
    return $true
}
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
$script:rows | ForEach-Object { Write-Output $_ }
