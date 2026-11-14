Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
"@
$h = [W.U]::FindWindow("DockStripWindow", $null)
Write-Output ("strip hwnd=" + $h + " iswindow=" + [W.U]::IsWindow($h) + " hung=" + [W.U]::IsHungAppWindow($h))
$res = [IntPtr]::Zero
$t0 = Get-Date
$ok = [W.U]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1500, [ref]$res)
Write-Output ("ping ok={0} took={1:N0}ms" -f $ok, ((Get-Date) - $t0).TotalMilliseconds)
