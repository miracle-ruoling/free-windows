param([string]$Hex = '0x503E4')
Add-Type -Namespace IW -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
'@
$h = [IntPtr][Convert]::ToInt64($Hex, 16)
$cls = New-Object System.Text.StringBuilder 128
[void][IW.U]::GetClassName($h, $cls, 128)
$p = [uint32]0
[void][IW.U]::GetWindowThreadProcessId($h, [ref]$p)
Write-Output ("hwnd=$Hex isWindow=" + [IW.U]::IsWindow($h) + " visible=" + [IW.U]::IsWindowVisible($h) + " pid=$p cls=" + $cls.ToString())
