$root = 'HKCU:\Control Panel\NotifyIconSettings'
if (-not (Test-Path $root)) { Write-Output 'no NotifyIconSettings key'; exit }
$subs = Get-ChildItem $root
Write-Output ("entries: " + $subs.Count)
foreach ($s in $subs) {
    $p = Get-ItemProperty $s.PSPath
    $names = ($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $_.Name }) -join ','
    Write-Output ("--- " + $s.PSChildName)
    Write-Output ("    exec=" + $p.ExecutablePath + " tip=" + $p.InitialTooltip + " promoted=" + $p.IsPromoted)
    Write-Output ("    values: " + $names)
}
