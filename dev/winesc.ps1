Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
"@
# tap Win, wait for the Start menu, then Esc it away
[W.U]::keybd_event(0x5B, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 120
[W.U]::keybd_event(0x5B, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
[W.U]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[W.U]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 600
Write-Output "win+esc done"
