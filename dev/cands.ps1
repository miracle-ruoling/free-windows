Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
'@

$skip = 'Shell_TrayWnd','Shell_SecondaryTrayWnd','Progman','WorkerW','Windows.UI.Core.CoreWindow'
$all = New-Object System.Collections.Generic.List[object]

$cb = [W.U+EnumProc]{
    param($h, $l)
    $procId = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$procId)
    $sb = New-Object System.Text.StringBuilder 256
    [void][W.U]::GetWindowText($h, $sb, 256)
    $cl = New-Object System.Text.StringBuilder 128
    [void][W.U]::GetClassName($h, $cl, 128)
    $ex = [W.U]::GetWindowLong($h, -20)
    $owner = [W.U]::GetWindow($h, 4)
    $cloaked = 0
    try { [void][W.U]::DwmGetWindowAttribute($h, 14, [ref]$cloaked, 4) } catch {}
    $flags = ''
    if ($ex -band 0x80) { $flags += 'TOOL ' }
    if ($ex -band 0x40000) { $flags += 'APP ' }
    if ($ex -band 0x8000000) { $flags += 'NOACT ' }
    $script:all.Add([pscustomobject]@{
        Hwnd = $h; Pid = $procId; Class = $cl.ToString(); Title = $sb.ToString()
        Vis = [W.U]::IsWindowVisible($h); Iconic = [W.U]::IsIconic($h)
        Owner = ($owner -ne [IntPtr]::Zero); Ex = $flags; Cloaked = $cloaked
    })
    return $true
}
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)

function OldRule($w) {
    if (-not $w.Vis) { return $false }
    if ($w.Cloaked) { return $false }
    if ($w.Owner) { return $false }
    if ($w.Ex -match 'TOOL') { return $false }
    if ($script:skip -contains $w.Class) { return $false }
    if ($w.Title.Length -eq 0) { return $false }
    return $true
}
function NewRule($w) {
    if (-not $w.Vis) { return $false }
    if ($w.Cloaked) { return $false }
    $app = $w.Ex -match 'APP'
    $tool = $w.Ex -match 'TOOL'
    if (-not ($app -or ((-not $tool) -and (-not $w.Owner)))) { return $false }
    if ($script:skip -contains $w.Class) { return $false }
    return $true
}

$old = $all | Where-Object { OldRule $_ }
$new = $all | Where-Object { NewRule $_ }

Write-Output ("windows=" + $all.Count + "  oldRule=" + $old.Count + "  newRule=" + $new.Count)

Write-Output "---- only in NEW (would be added) ----"
foreach ($w in $new) {
    $inOld = $old | Where-Object { $_.Hwnd -eq $w.Hwnd }
    if (-not $inOld) {
        Write-Output ("  hwnd={0} p={1} vis={2} ic={3} owner={4} ex=[{5}] class={6} title='{7}'" -f $w.Hwnd, $w.Pid, $w.Vis, $w.Iconic, $w.Owner, $w.Ex, $w.Class, $w.Title)
    }
}
Write-Output "---- only in OLD (would be dropped) ----"
foreach ($w in $old) {
    $inNew = $new | Where-Object { $_.Hwnd -eq $w.Hwnd }
    if (-not $inNew) {
        Write-Output ("  hwnd={0} p={1} vis={2} ic={3} owner={4} ex=[{5}] class={6} title='{7}'" -f $w.Hwnd, $w.Pid, $w.Vis, $w.Iconic, $w.Owner, $w.Ex, $w.Class, $w.Title)
    }
}
Write-Output "---- new rule set ----"
foreach ($w in $new) {
    Write-Output ("  {0,-12} ic={1,-5} ex=[{2,-14}] {3}  |  {4}" -f $w.Hwnd, $w.Iconic, $w.Ex, $w.Title, $w.Class)
}
