param([long]$Hwnd = 0x201DC, [int]$Uid = 3, [int]$Msg = 0x8001, [long]$Fg = 196656)
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
$script:pids = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
function Snap {
    $script:rows = New-Object System.Collections.Generic.List[string]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        if (-not [W.U]::IsWindowVisible($h)) { return $true }
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $cl = New-Object System.Text.StringBuilder 60
        [void][W.U]::GetClassName($h, $cl, 60)
        $script:rows.Add(("hwnd={0} {1}x{2}@{3},{4} {5}" -f $h, ($r.Right-$r.Left), ($r.Bottom-$r.Top), $r.Left, $r.Top, $cl.ToString()))
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:rows
}
$before = Snap
Write-Output ("before: " + $before.Count)
[void][W.U]::SetCursorPos(1200, 400)
Start-Sleep -Milliseconds 200
$ok = [W.U]::SetForegroundWindow([IntPtr]$Fg)
Write-Output ("SetForegroundWindow -> " + $ok)
Start-Sleep -Milliseconds 350
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
Start-Sleep -Milliseconds 120
[void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Start-Sleep -Milliseconds 1500
$after = Snap
$new = @($after | Where-Object { $x = $_; -not ($before | Where-Object { $_ -eq $x }) })
Write-Output ("after fg+post: new = " + $new.Count)
foreach ($x in $new) { Write-Output ("   " + $x) }
