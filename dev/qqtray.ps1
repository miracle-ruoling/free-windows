param([long]$Hwnd = 0x120E10, [int]$Uid = 3, [int]$Msg = 0x8001)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()

$script:pids = @(Get-Process -Name qq -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$ownerPid = [uint32]0
[void][W.U]::GetWindowThreadProcessId([IntPtr]$Hwnd, [ref]$ownerPid)
Write-Output ("target hwnd=0x{0:X} pid={1} uid={2} msg=0x{3:X}" -f $Hwnd, $ownerPid, $Uid, $Msg)

function Snapshot {
    $script:rows = New-Object System.Collections.Generic.List[object]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $cl = New-Object System.Text.StringBuilder 120
        [void][W.U]::GetClassName($h, $cl, 120)
        $script:rows.Add([pscustomobject]@{ Hwnd = $h; Cls = $cl.ToString(); Vis = [W.U]::IsWindowVisible($h); R = $r })
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:rows
}

$target = [IntPtr]$Hwnd
$before = Snapshot
Write-Output ("windows before: " + $before.Count)

$combos = @(
    @{ name = 'UP only';     msgs = @(0x0205) },
    @{ name = 'DOWN+UP';     msgs = @(0x0204, 0x0205) },
    @{ name = 'CONTEXTMENU'; msgs = @(0x007B) },
    @{ name = 'UP + uid=1';  msgs = @(0x0205); uid = 1 }
)

$yy = 300
foreach ($c in $combos) {
    [void][W.U]::SetCursorPos(900, $yy)
    Start-Sleep -Milliseconds 200
    $u = if ($c.ContainsKey('uid')) { $c.uid } else { $Uid }
    foreach ($m in $c.msgs) {
        [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$u, [IntPtr]$m)
        Start-Sleep -Milliseconds 250
    }
    Start-Sleep -Milliseconds 800
    $after = Snapshot
    $new = @($after | Where-Object { $h = $_.Hwnd; -not ($before | Where-Object { $_.Hwnd -eq $h }) })
    Write-Output ("== {0}: new windows = {1}" -f $c.name, $new.Count)
    foreach ($w in $new) {
        Write-Output ("     hwnd={0} vis={1} rect={2},{3}-{4},{5} class={6}" -f $w.Hwnd, $w.Vis, $w.R.Left, $w.R.Top, $w.R.Right, $w.R.Bottom, $w.Cls)
    }
    # dismiss whatever opened, without clicking on the user's desktop
    foreach ($w in $new) { [void][W.U]::PostMessage($w.Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
    [void][W.U]::SetCursorPos(1200, 20)
    Start-Sleep -Milliseconds 500
    $before = Snapshot
    $yy += 60
}
