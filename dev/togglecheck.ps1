param([long]$Popup = 4524716, [long]$TrayHost = 0x106CE, [int]$Uid = 0, [int]$Msg = 0x400)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint ga);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
"@
[void][W.U]::SetProcessDPIAware()
$p = [IntPtr]$Popup
function OnScreen {
    $r = New-Object W.U+RECT
    if (-not [W.U]::GetWindowRect($p, [ref]$r)) { return $false }
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    $hits = 0
    foreach ($fx in 0.25, 0.5, 0.75) {
        foreach ($fy in 0.15, 0.5, 0.85) {
            $pt = New-Object W.U+POINT
            $pt.X = [int]($r.Left + $w * $fx)
            $pt.Y = [int]($r.Top + $h * $fy)
            $hit = [W.U]::WindowFromPoint($pt)
            if ($hit -eq [IntPtr]::Zero) { continue }
            if ($hit -eq $p -or [W.U]::GetAncestor($hit, 2) -eq $p) { $hits++ }
        }
    }
    return ($hits -ge 2)
}
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($p, [ref]$r)
Write-Output ("rect {0},{1}-{2},{3} onscreen={4}" -f $r.Left, $r.Top, $r.Right, $r.Bottom, (OnScreen))
[void][W.U]::PostMessage([IntPtr]$TrayHost, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
[void][W.U]::PostMessage([IntPtr]$TrayHost, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Start-Sleep -Milliseconds 1200
Write-Output ("after toggle: onscreen=" + (OnScreen))
