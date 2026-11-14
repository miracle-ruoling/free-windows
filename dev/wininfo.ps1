param([long]$Hwnd = 4524716)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
'@
$m = [IntPtr]$Hwnd
$cls = New-Object System.Text.StringBuilder 128
[void][W.U]::GetClassName($m, $cls, 128)
$style = [W.U]::GetWindowLong($m, -16)
$ex = [W.U]::GetWindowLong($m, -20)
Write-Output ("class={0} style=0x{1:X} ex=0x{2:X} exists={3} visible={4}" -f $cls.ToString(), $style, $ex, [W.U]::IsWindow($m), [W.U]::IsWindowVisible($m))
