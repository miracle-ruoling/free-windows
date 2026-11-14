param([string]$Proc = 'pythonw')
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$p = Get-Process $Proc -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output "no $Proc"; exit 1 }
Write-Output ("target pid=" + $p.Id)
$targets = New-Object System.Collections.Generic.List[IntPtr]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $pid2 = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $p.Id -and [W.U]::IsWindowVisible($h)) {
        $sb = New-Object System.Text.StringBuilder 128
        [void][W.U]::GetWindowText($h, $sb, 128)
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        Write-Output ("  win " + $h + " '" + $sb.ToString() + "' " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
        $targets.Add($h)
    }
    return $true
}
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
foreach ($h in $targets) {
    [void][W.U]::PostMessage($h, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CANCELMODE
    [void][W.U]::PostMessage($h, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero)     # WM_KEYDOWN VK_ESCAPE
    [void][W.U]::PostMessage($h, 0x0101, [IntPtr]0x1B, [IntPtr]0xC0000001) # WM_KEYUP
}
Write-Output ("posted to " + $targets.Count + " window(s)")
