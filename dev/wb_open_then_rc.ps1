param([long]$Hwnd = 0x10B34, [int]$Uid = 3, [int]$Msg = 0x8001)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
"@
[void][W.U]::SetProcessDPIAware()
$script:pids = @(Get-Process -Name workbuddy -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
function Windows {
    $script:rows = New-Object System.Collections.Generic.List[object]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $cl = New-Object System.Text.StringBuilder 60
        [void][W.U]::GetClassName($h, $cl, 60)
        $script:rows.Add([pscustomobject]@{ H = $h; Vis = [W.U]::IsWindowVisible($h); W = ($r.Right-$r.Left); Ht = ($r.Bottom-$r.Top); Cls = $cl.ToString() })
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:rows
}
$start = Windows
[void][W.U]::SetCursorPos(1200, 400)
Start-Sleep -Milliseconds 200
# open the app the way a user would: left click its tray icon
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0201)
Start-Sleep -Milliseconds 100
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0202)
Start-Sleep -Milliseconds 1500
$now = Windows
$shown = $now | Where-Object { $_.Vis -and $_.W -gt 200 }
Write-Output ("visible big windows after left click: " + $shown.Count)
foreach ($w in $shown) { Write-Output ("   hwnd=" + $w.H + " " + $w.W + "x" + $w.Ht + " " + $w.Cls) }
if ($shown.Count -gt 0) {
    $target = $shown[0].H
    $ok = [W.U]::SetForegroundWindow($target)
    Write-Output ("SetForegroundWindow(" + $target + ") -> " + $ok)
    Start-Sleep -Milliseconds 400
    $before = Windows
    [void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
    Start-Sleep -Milliseconds 120
    [void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
    Start-Sleep -Milliseconds 1500
    $after = Windows
    $new = @($after | Where-Object { $x = $_.H; -not ($before | Where-Object { $_.H -eq $x }) })
    Write-Output ("after right click with app in front: new windows = " + $new.Count)
    foreach ($w in $new) { Write-Output ("   hwnd=" + $w.H + " vis=" + $w.Vis + " " + $w.W + "x" + $w.Ht + " " + $w.Cls) }
}
