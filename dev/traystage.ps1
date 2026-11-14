param([long]$Hwnd = 0x120E10, [int]$Uid = 3, [int]$Msg = 0x8001, [string]$Tag = 'qq')
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@
[void][W.U]::SetProcessDPIAware()

$target = [IntPtr]$Hwnd
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Shot([string]$name) {
    $bmp = New-Object System.Drawing.Bitmap 420, 430
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(760, 0, 0, 0, (New-Object System.Drawing.Size 420, 430))
    $g.Dispose()
    $bmp.Save("$here\$name", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# park the cursor where the real tray menu would appear
[void][W.U]::SetCursorPos(900, 300)
Start-Sleep -Milliseconds 300
Shot "$Tag`_0_before.png"

# stage 1: right button up only (what dock posts today)
[void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Start-Sleep -Milliseconds 900
Shot "$Tag`_1_up.png"

# dismiss: deactivate + kill focus on the popup owner
[void][W.U]::PostMessage($target, 0x0006, [IntPtr]::Zero, [IntPtr]::Zero)
[void][W.U]::PostMessage($target, 0x0008, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 700
Shot "$Tag`_2_cleared.png"

# stage 2: right button down, then up (a real click)
[void][W.U]::SetCursorPos(900, 300)
Start-Sleep -Milliseconds 200
[void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0204)
Start-Sleep -Milliseconds 90
[void][W.U]::PostMessage($target, [uint32]$Msg, [IntPtr]$Uid, [IntPtr]0x0205)
Start-Sleep -Milliseconds 900
Shot "$Tag`_3_downup.png"
Write-Output "shots written: $Tag`_0_before / _1_up / _2_cleared / _3_downup"
