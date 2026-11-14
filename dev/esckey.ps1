Add-Type -Namespace K2 -Name Kb -MemberDefinition @'
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string name);
'@
$h = [K2.Kb]::FindWindow('#32768', $null)
Write-Output ("menu window: " + $h)
# post a real Escape to whatever owns the popup
[K2.Kb]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[K2.Kb]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
Write-Output ("after esc: " + [K2.Kb]::FindWindow('#32768', $null))
