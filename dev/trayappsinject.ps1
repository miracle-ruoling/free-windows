$os = Get-CimInstance Win32_OperatingSystem
$up = (Get-Date) - $os.LastBootUpTime
Write-Output ("uptime: " + [int]$up.TotalHours + "h " + $up.Minutes + "m   lastBoot=" + $os.LastBootUpTime)
$names = @('explorer', 'RvRvpnGui', 'aTrustTray', 'wallpaper64', 'wallpaper32', 'uu',
           'NVDisplay.Container', 'windhawk', 'pythonw', 'msedge', 'LZTray', 'TranslucentTB')
foreach ($n in $names) {
    $ps = Get-Process $n -ErrorAction SilentlyContinue
    if (-not $ps) { Write-Output ($n.PadRight(20) + ' not running'); continue }
    foreach ($p in $ps) {
        $mods = $null
        try { $mods = $p.Modules } catch { }
        if (-not $mods) { Write-Output ($n.PadRight(20) + ' pid=' + $p.Id + '  (unreadable)'); continue }
        $hit = $mods | Where-Object { $_.ModuleName -like '*tray-icons*' }
        $start = ''
        try { $start = ' started=' + $p.StartTime.ToString('HH:mm') } catch { }
        Write-Output ($n.PadRight(20) + ' pid=' + $p.Id + '  bridge=' + $(if ($hit) { 'YES' } else { 'no ' }) + $start)
    }
}
