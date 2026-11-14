param([switch]$Esc)
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
'@
if ($Esc) {
    [W.U]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero)
    [W.U]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero)
    Write-Output 'esc'
}
