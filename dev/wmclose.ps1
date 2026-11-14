param([long]$Hwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
"@
$m = [IntPtr]$Hwnd
Write-Output ("exists before: " + [W.U]::IsWindow($m))
[void][W.U]::PostMessage($m, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
Start-Sleep -Milliseconds 900
Write-Output ("exists after: " + [W.U]::IsWindow($m))
