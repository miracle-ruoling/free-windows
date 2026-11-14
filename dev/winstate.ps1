Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
function Dump($label, $h) {
    if ($h -eq [IntPtr]::Zero) { Write-Output ($label + ': not found'); return }
    $r = New-Object W.U+RECT
    [void][W.U]::GetWindowRect($h, [ref]$r)
    Write-Output ($label + ': hwnd=' + $h + ' visible=' + [W.U]::IsWindowVisible($h) + ' rect=' + $r.Left + ',' + $r.Top + ' ' + ($r.Right-$r.Left) + 'x' + ($r.Bottom-$r.Top))
}
Dump 'grid ' ([W.U]::FindWindow('DockGridWindow', [NullString]::Value))
Dump 'strip' ([W.U]::FindWindow('DockStripWindow', [NullString]::Value))
$menu = [W.U]::FindWindow('#32768', [NullString]::Value)
Dump 'menu ' $menu
$fg = [W.U]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder 128
[void][W.U]::GetClassName($fg, $sb, 128)
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($fg, [ref]$r)
Write-Output ('foreground: ' + $fg + ' class=' + $sb.ToString() + ' rect=' + $r.Left + ',' + $r.Top + ' ' + ($r.Right-$r.Left) + 'x' + ($r.Bottom-$r.Top))
