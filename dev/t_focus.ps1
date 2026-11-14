param()
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
Add-Type -Namespace K -Name Ki -MemberDefinition @'
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
'@
if (-not (Open-Grid)) { Write-Output 'grid did not open'; exit 1 }
Start-Sleep -Milliseconds 500
Show-State 'grid open'
Write-Output 'sending Alt+Tab'
[K.Ki]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)      # Alt down
[K.Ki]::keybd_event(0x09, 0, 0, [UIntPtr]::Zero)      # Tab down
Start-Sleep -Milliseconds 80
[K.Ki]::keybd_event(0x09, 0, 2, [UIntPtr]::Zero)      # Tab up
[K.Ki]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)      # Alt up
Start-Sleep -Milliseconds 800
Show-State 'after Alt+Tab'
