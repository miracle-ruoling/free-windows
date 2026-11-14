param([int]$Seconds = 12)
$vals = @()
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    try {
        $s = (Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop).CounterSamples
        $vals += ($s | Where-Object { $_.InstanceName -like "*engtype_3d*" } |
                  Measure-Object -Property CookedValue -Sum).Sum
    } catch {}
}
if ($vals.Count) {
    $m = $vals | Measure-Object -Average -Maximum
    "system 3D GPU: avg {0:N1}%  max {1:N1}%  samples {2}" -f $m.Average, $m.Maximum, $vals.Count
} else { "no data" }
