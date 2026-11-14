param([int]$Row = 2, [int]$Col = 1, [int]$Times = 3)
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
"@
[void][W.U]::SetProcessDPIAware()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
for ($i = 1; $i -le $Times; $i++) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'gridrc.ps1') -Row $Row -Col $Col -Out ("loop_" + $i + ".png") -Wait 1500 | Out-Null
    [void][W.U]::SetCursorPos(1870, 1046)
    Start-Sleep -Milliseconds 200
    [W.U]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [W.U]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 1200
    Write-Output ("--- round " + $i + " done")
}
