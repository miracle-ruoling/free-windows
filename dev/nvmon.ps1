param([int]$Seconds = 45, [string]$Out = 'nvmon.txt')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here 'bridgedump.exe'
$lines = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = ''
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $out = & $exe 2>&1
    $head = ($out | Select-Object -First 1)
    $count = if ($head -match 'count=(\d+)') { [int]$Matches[1] } else { -1 }
    $ver = if ($head -match 'version=(\d+)') { [int]$Matches[1] } else { -1 }
    $nv = ($out | Where-Object { $_ -match 'NVDisplay' }).Count
    $sig = "$ver|$count|$nv"
    if ($sig -ne $last) {
        $lines += ("{0,6:N1}s  ver={1,-6} count={2,-3} nvidia={3}" -f $sw.Elapsed.TotalSeconds, $ver, $count, $nv)
        $last = $sig
    }
    Start-Sleep -Milliseconds 700
}
$lines | Set-Content -Path (Join-Path $here $Out) -Encoding UTF8
Write-Output ("wrote $Out, " + $lines.Count + " change(s)")
