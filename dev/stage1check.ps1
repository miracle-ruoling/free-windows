param([long]$Popup = 4524716)
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
Write-Output ("before: onscreen=" + (OnScreen))
[void][W.U]::PostMessage($p, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)
[void][W.U]::PostMessage($p, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero)
[void][W.U]::PostMessage($p, 0x0101, [IntPtr]0x1B, [IntPtr]0xC0000001)
[void][W.U]::PostMessage($p, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)
[void][W.U]::PostMessage($p, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1000
Write-Output ("after stage1: onscreen=" + (OnScreen))
