param([long]$Hwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$m = [IntPtr]$Hwnd
function State { $r = New-Object W.U+RECT; [void][W.U]::GetWindowRect($m, [ref]$r); return ("vis={0} rect={1},{2}-{3},{4}" -f [W.U]::IsWindowVisible($m), $r.Left, $r.Top, $r.Right, $r.Bottom) }

Write-Output ("start: " + (State))
[void][W.U]::SendMessage($m, 0x0086, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_NCACTIVATE false
[void][W.U]::SendMessage($m, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_ACTIVATE WA_INACTIVE
Start-Sleep -Milliseconds 600
Write-Output ("after ncactivate/activate: " + (State))

[void][W.U]::PostMessage($m, 0x0020, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_SETCURSOR
[void][W.U]::PostMessage($m, 0x02A3, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_MOUSELEAVE
[void][W.U]::PostMessage($m, 0x001C, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_ACTIVATEAPP false
Start-Sleep -Milliseconds 600
Write-Output ("after mouseleave/activateapp: " + (State))
