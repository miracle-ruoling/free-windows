param([long]$Hwnd = 0x10B34, [int]$Uid = 3, [int]$Msg = 0x8001, [string]$Proc = 'workbuddy')
Add-Type -Namespace W -Name U -MemberDefinition @"
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
"@
[void][W.U]::SetProcessDPIAware()
$script:pids = @(Get-Process -Name $Proc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
function Snap {
    $script:rows = New-Object System.Collections.Generic.List[string]
    $cb = [W.U+EnumProc]{
        param($h, $l)
        $wp = [uint32]0
        [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
        if ($script:pids -notcontains $wp) { return $true }
        $r = New-Object W.U+RECT
        [void][W.U]::GetWindowRect($h, [ref]$r)
        $cl = New-Object System.Text.StringBuilder 60
        [void][W.U]::GetClassName($h, $cl, 60)
        $script:rows.Add(("hwnd={0} vis={1} {2}x{3}@{4},{5} {6}" -f $h, [W.U]::IsWindowVisible($h), ($r.Right-$r.Left), ($r.Bottom-$r.Top), $r.Left, $r.Top, $cl.ToString()))
        return $true
    }
    [void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:rows
}
$seqs = @(
  @{ n='DOWN+UP uid3'; u=$Uid; s=@(0x0204,0x0205) },
  @{ n='DOWN+UP uid1'; u=1;    s=@(0x0204,0x0205) },
  @{ n='LDOWN+LUP uid3'; u=$Uid; s=@(0x0201,0x0202) },
  @{ n='MMOVE'; u=$Uid; s=@(0x0200) },
  @{ n='NIN_SELECT'; u=$Uid; s=@(0x0400) }
)
$before = Snap
foreach ($c in $seqs) {
    [void][W.U]::SetCursorPos(1000, 300)
    Start-Sleep -Milliseconds 200
    foreach ($m in $c.s) { [void][W.U]::PostMessage([IntPtr]$Hwnd, [uint32]$Msg, [IntPtr]$c.u, [IntPtr]$m) ; Start-Sleep -Milliseconds 120 }
    Start-Sleep -Milliseconds 900
    $after = Snap
    $new = @($after | Where-Object { $x = $_; -not ($before | Where-Object { $_ -eq $x }) })
    Write-Output ("== " + $c.n + " : new/changed = " + $new.Count)
    foreach ($x in $new) { Write-Output ("     " + $x) }
    $before = Snap
}
