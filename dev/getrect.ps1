Add-Type -Namespace W -Name T -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct NOTIFYICONIDENTIFIER { public int cbSize; public IntPtr hWnd; public uint uID; public Guid guidItem; }
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }
[DllImport("shell32.dll")]
public static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER id, out RECT rc);
[DllImport("user32.dll", CharSet=CharSet.Unicode)]
public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
'@
$tray = [W.T]::FindWindow('Shell_TrayWnd', [NullString]::Value)
$tr = New-Object W.T+RECT
[void][W.T]::GetWindowRect($tray, [ref]$tr)
Write-Output ("Shell_TrayWnd visible=" + [W.T]::IsWindowVisible($tray) + " rect=" + $tr.Left + "," + $tr.Top + " " + ($tr.Right-$tr.Left) + "x" + ($tr.Bottom-$tr.Top))

$root = 'HKCU:\Control Panel\NotifyIconSettings'
$ok = 0; $fail = 0
foreach ($s in Get-ChildItem $root) {
    $p = Get-ItemProperty $s.PSPath
    if (-not $p.IconGuid) { continue }
    $id = New-Object W.T+NOTIFYICONIDENTIFIER
    $id.cbSize = 32
    $id.hWnd = [IntPtr]::Zero
    $id.uID = 0
    $id.guidItem = [Guid]$p.IconGuid.ToString()
    $rc = New-Object W.T+RECT
    $hr = [W.T]::Shell_NotifyIconGetRect([ref]$id, [ref]$rc)
    if ($hr -eq 0) {
        $ok++
        Write-Output ("  OK  " + [System.IO.Path]::GetFileName($p.ExecutablePath) + "  rect=" + $rc.Left + "," + $rc.Top)
        if ($ok -ge 6) { break }
    } else { $fail++ }
}
Write-Output ("guid icons: ok=" + $ok + " fail=" + $fail)
