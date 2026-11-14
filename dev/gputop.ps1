$s = (Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop).CounterSamples |
     Where-Object { $_.InstanceName -like "*engtype_3d*" }
$byPid = @{}
foreach ($x in $s) {
    if ($x.InstanceName -match 'pid_(\d+)_') {
        $p = [int]$Matches[1]
        if (-not $byPid.ContainsKey($p)) { $byPid[$p] = 0 }
        $byPid[$p] += $x.CookedValue
    }
}
$byPid.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object {
    $proc = Get-Process -Id $_.Key -ErrorAction SilentlyContinue
    $name = if ($proc) { $proc.ProcessName } else { "?" }
    "{0,-22} pid={1,-6} 3D {2,5:N1}%" -f $name, $_.Key, $_.Value
}
"total 3D: {0:N1}%" -f (($byPid.Values | Measure-Object -Sum).Sum)
