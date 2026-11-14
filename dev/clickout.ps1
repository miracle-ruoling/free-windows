param([long]$MenuHwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$m = [IntPtr]$MenuHwnd
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($m, [ref]$r)
Write-Output ("rect {0},{1}-{2},{3} visible={4}" -f $r.Left, $r.Top, $r.Right, $r.Bottom, [W.U]::IsWindowVisible($m))
# a click far outside the popup, delivered to the popup itself (it holds capture
# like a real menu does) - WPF/Tk/Qt close on that
$lpD = [IntPtr](((-40 -shl 16) -bor (-40 -band 0xFFFF)))
[void][W.U]::PostMessage($m, 0x0201, [IntPtr]1, $lpD)   # WM_LBUTTONDOWN
Start-Sleep -Milliseconds 60
[void][W.U]::PostMessage($m, 0x0202, [IntPtr]0, $lpD)   # WM_LBUTTONUP
Start-Sleep -Milliseconds 900
Write-Output ("visible after outside-click: " + [W.U]::IsWindowVisible($m))
