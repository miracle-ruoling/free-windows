Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
'@
$h = [W.K]::OpenFileMapping(0x0004, $false, 'Local\DockTrayBridge_v1')
if ($h -eq [IntPtr]::Zero) {
    Write-Output ("mapping: NOT FOUND (err " + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + ")")
} else {
    Write-Output 'mapping: FOUND'
    [void][W.K]::CloseHandle($h)
}
$p = Get-Process explorer -ErrorAction SilentlyContinue
foreach ($proc in $p) {
    $mods = $null
    try { $mods = $proc.Modules } catch { }
    if (-not $mods) { Write-Output ("explorer pid=" + $proc.Id + " modules unreadable"); continue }
    $hits = $mods | Where-Object { $_.ModuleName -like '*tray-icons*' -or $_.ModuleName -like '*windhawk*' }
    Write-Output ("explorer pid=" + $proc.Id + " modules=" + $mods.Count)
    if ($hits) { $hits | ForEach-Object { Write-Output ("  loaded: " + $_.ModuleName) } }
    else { Write-Output '  no windhawk/tray module loaded' }
}
