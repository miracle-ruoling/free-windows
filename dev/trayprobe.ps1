Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr after, string c, string w);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
'@
[void][W.U]::SetProcessDPIAware()
Write-Output ("os: " + [System.Environment]::OSVersion.VersionString)
$tray = [W.U]::FindWindow("Shell_TrayWnd", [NullString]::Value)
Write-Output ("Shell_TrayWnd = " + $tray)
function Dump($h, $depth) {
    $i = 0
    $c = [W.U]::FindWindowEx($h, [IntPtr]::Zero, [NullString]::Value, [NullString]::Value)
    while ($c -ne [IntPtr]::Zero -and $i -lt 30) {
        $cls = New-Object System.Text.StringBuilder 128
        [void][W.U]::GetClassName($c, $cls, 128)
        $tx = New-Object System.Text.StringBuilder 128
        [void][W.U]::GetWindowText($c, $tx, 128)
        $pad = ' ' * ($depth * 2)
        Write-Output ($pad + "+ " + $cls.ToString() + " '" + $tx.ToString() + "' vis=" + [W.U]::IsWindowVisible($c))
        if ($cls.ToString() -eq 'ToolbarWindow32') {
            $n = [W.U]::SendMessage($c, 0x0418, [IntPtr]::Zero, [IntPtr]::Zero)  # TB_BUTTONCOUNT
            Write-Output ($pad + "   TB_BUTTONCOUNT = " + $n)
        }
        if ($depth -lt 3) { Dump $c ($depth + 1) }
        $c = [W.U]::FindWindowEx($h, $c, [NullString]::Value, [NullString]::Value)
        $i++
    }
}
if ($tray -ne [IntPtr]::Zero) { Dump $tray 1 }
$ov = [W.U]::FindWindow("NotifyIconOverflowWindow", [NullString]::Value)
Write-Output ("NotifyIconOverflowWindow = " + $ov)
if ($ov -ne [IntPtr]::Zero) { Dump $ov 1 }
