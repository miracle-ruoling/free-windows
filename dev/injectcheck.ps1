$names = @('windhawk', 'TranslucentTB', 'PowerToys', 'Radmin', 'msedge', 'explorer',
           'WeChat', 'QQ', 'steam', 'Telegram')
foreach ($n in $names) {
    $ps = Get-Process $n -ErrorAction SilentlyContinue
    foreach ($p in $ps) {
        $mods = $null
        try { $mods = $p.Modules } catch { }
        if (-not $mods) { Write-Output ($n + ' pid=' + $p.Id + ' (modules unreadable)'); continue }
        $hit = $mods | Where-Object { $_.ModuleName -like '*tray-icons*' }
        Write-Output ($n + ' pid=' + $p.Id + ' mods=' + $mods.Count + ' bridge=' + $(if ($hit) { 'YES' } else { 'no' }))
    }
}
