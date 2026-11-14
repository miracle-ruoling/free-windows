param([long]$Hwnd = 0)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
"@
$m = [IntPtr]$Hwnd
Write-Output ("visible before: " + [W.U]::IsWindowVisible($m))
$seq = @(@(0x001F, 0), @(0x0100, 0x1B), @(0x0101, 0x1B), @(0x0006, 0), @(0x0008, 0))
foreach ($x in $seq) {
    $ok = [W.U]::PostMessage($m, [uint32]$x[0], [IntPtr]::Zero, [IntPtr]$x[1])
    Write-Output ("  post 0x{0:X} -> {1}" -f $x[0], $ok)
    Start-Sleep -Milliseconds 60
}
Start-Sleep -Milliseconds 700
Write-Output ("visible after: " + [W.U]::IsWindowVisible($m))
