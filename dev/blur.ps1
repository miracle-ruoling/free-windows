param([string]$Proc = 'qq', [int]$CX = 820, [int]$CY = 0, [int]$W = 430, [int]$H = 340, [string]$Out = 'x.png')
# blur every visible window of the given processes (closes tray panels that
# ignore Esc but go away on focus loss)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
public delegate bool EnumProc(IntPtr h, IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@
$ids = @(Get-Process -Name $Proc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$script:v = New-Object System.Collections.Generic.List[IntPtr]
$cb = [W.U+EnumProc]{
    param($h, $l)
    $wp = [uint32]0
    [void][W.U]::GetWindowThreadProcessId($h, [ref]$wp)
    if ($script:ids -notcontains $wp) { return $true }
    if ([W.U]::IsWindowVisible($h)) { $script:v.Add($h) }
    return $true
}
$script:ids = $ids
[void][W.U]::EnumWindows($cb, [IntPtr]::Zero)
foreach ($h in $script:v) {
    [void][W.U]::PostMessage($h, 0x001F, [IntPtr]::Zero, [IntPtr]::Zero)
    [void][W.U]::PostMessage($h, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)
    [void][W.U]::PostMessage($h, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)
}
Write-Output ("blurred " + $script:v.Count + " windows of " + $Proc)
