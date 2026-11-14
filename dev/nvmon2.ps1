param([int]$Seconds = 300, [string]$Out = 'nvmon2.txt')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here 'bridgedump.exe'
$sw = [Diagnostics.Stopwatch]::StartNew()
$prevVer = -1
$prevCount = -1
$prevNv = -1
$changes = @()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $out = & $exe 2>&1
    $head = $out | Select-Object -First 1
    $count = -1; $ver = -1
    if ("$head" -match 'version=(\d+)') { $ver = [int]$Matches[1] }
    if ("$head" -match 'count=(\d+)') { $count = [int]$Matches[1] }
    $nv = @($out | Where-Object { "$_" -match 'NVDisplay' }).Count
    if ($ver -ne $prevVer -or $count -ne $prevCount -or $nv -ne $prevNv) {
        $changes += ("{0,7:N0}s ver={1,-6} count={2,-3} nvidia={3}" -f $sw.Elapsed.TotalSeconds, $ver, $count, $nv)
        $prevVer = $ver; $prevCount = $count; $prevNv = $nv
    }
    Start-Sleep -Milliseconds 400
}
$changes | Set-Content -Path (Join-Path $here $Out) -Encoding UTF8
Write-Output ("monitored {0}s, {1} change(s)" -f $Seconds, $changes.Count)
