param([long]$Hwnd = 0x120E10, [int]$Uid = 3, [int]$Msg = 0x8001, [string]$Proc = 'qq')
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
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][W.U]::SetProcessDPIAware()
$script:pids = @(Get-Process -Name $Proc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
Write-Output ("proc=$Proc pids=" + ($script:pids -join ','))
$target = [IntPtr]$Hwnd

function MenuRects {
    $script:out = New-Object System.Collections.Generic.List[string]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        if (-not [W.U]::IsWindowVisible($h)) { return $true }
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
        if ($w -le 0 -or $hh -le 0) { return $true }
        $cl = New-Object System.Text.StringBuilder 60
        [void][W.U]::GetClassName($h, $cl, 60)
        $script:out.Add(("hwnd={0} {1}x{2} at {3},{4} {5}" -f $h, $w, $hh, $r.Left, $r.Top, $cl.ToString()))
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:out
}

function Dismiss {
    # the tray panel is a non-activating popup: blur it, or nothing will close it
    $victims = New-Object System.Collections.Generic.List[IntPtr]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        if ([W.U]::IsWindowVisible($h)) { $script:victims.Add($h) }
        return $true
    }
    $script:victims = $victims
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    foreach ($v in $script:victims) {
        [void][W.U]::PostMessage($v, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)
        [void][W.U]::PostMessage($v, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 600
}

$combos = @(
    @{ n = 'UP';                 seq = @(0x0205) },
    @{ n = 'DOWN+UP';            seq = @(0x0204, 0x0205) },
    @{ n = 'DOWN+UP(300ms)';     seq = @(@(0x0204, 300), @(0x0205, 0)) },
    @{ n = 'CONTEXTMENU';        seq = @(0x007B) },
    @{ n = 'LBUTTONUP';          seq = @(0x0202) },
    @{ n = 'UP,uid=1';           seq = @(0x0205); uid = 1 },
    @{ n = 'UP x2';              seq = @(0x0205, 0x0205) }
)

foreach ($c in $combos) {
    Dismiss
    [void][W.U]::SetCursorPos(900, 300)
    Start-Sleep -Milliseconds 250
    $u = if ($c.ContainsKey('uid')) { $c.uid } else { $Uid }
    foreach ($step in $c.seq) {
        if ($step -is [array]) {
            [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$u, [IntPtr]$step[0])
            Start-Sleep -Milliseconds $step[1]
        } else {
            [void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$u, [IntPtr]$step)
        }
    }
    Start-Sleep -Milliseconds 1000
    $m = MenuRects
    Write-Output ("{0,-16} -> visible windows: {1}" -f $c.n, $m.Count)
    foreach ($x in $m) { Write-Output ("      " + $x) }
}
Dismiss
