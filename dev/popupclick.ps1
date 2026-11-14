param([long]$Hwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@
$m = [IntPtr]$Hwnd
function PackXY([int]$x, [int]$y) {
    $lo = [uint32]($x -band 0xFFFF)
    $hi = [uint32]($y -band 0xFFFF)
    return [IntPtr][int64](($hi -shl 16) -bor $lo)
}
Write-Output ("visible before: " + [W.U]::IsWindowVisible($m))
# mouse down outside the popup's content, but delivered to the popup itself:
# a WPF popup with StaysOpen=false closes on that hit test miss
[void][W.U]::SendMessage($m, 0x0201, [IntPtr]1, (PackXY 1200 900))
Start-Sleep -Milliseconds 120
[void][W.U]::SendMessage($m, 0x0202, [IntPtr]0, (PackXY 1200 900))
Start-Sleep -Milliseconds 900
Write-Output ("visible after: " + [W.U]::IsWindowVisible($m))
