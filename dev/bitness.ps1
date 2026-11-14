Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool IsWow64Process(IntPtr h, out bool wow64);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
$names = @('explorer','RvRvpnGui','aTrustTray','wallpaper64','uu','NVDisplay.Container',
           'windhawk','pythonw','msedge','LZTray','TranslucentTB','QQ','WorkBuddy',
           'SecurityHealthSystray','powerShell','GameViewer')
foreach ($n in $names) {
    $ps = Get-Process $n -ErrorAction SilentlyContinue
    if (-not $ps) { Write-Output ($n.PadRight(24) + ' not running'); continue }
    foreach ($p in $ps) {
        $h = [W.K]::OpenProcess(0x1000, $false, $p.Id)
        if ($h -eq [IntPtr]::Zero) { Write-Output ($n.PadRight(24) + ' pid=' + $p.Id + ' (no access)'); continue }
        $w = $false
        [void][W.K]::IsWow64Process($h, [ref]$w)
        [void][W.K]::CloseHandle($h)
        $bits = if ($w) { 'x86 (32-bit)' } else { 'x64' }
        $mods = $null
        try { $mods = $p.Modules } catch { }
        $bridge = if ($mods) { if ($mods | Where-Object { $_.ModuleName -like '*tray-icons*' }) { 'bridge=YES' } else { 'bridge=no' } } else { 'modules?' }
        Write-Output ($n.PadRight(24) + ' pid=' + $p.Id.ToString().PadRight(7) + $bits.PadRight(13) + $bridge)
    }
}
