$ids = @(9312, 30208, 14148, 10720)
foreach ($id in $ids) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p) { Write-Output ("pid=$id  <gone>"); continue }
    $path = $p.Path
    $wow = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $pe = [BitConverter]::ToInt32($bytes, 0x3C)
        $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
        $wow = if ($machine -eq 0x8664) { 'x64' } elseif ($machine -eq 0x14c) { 'x86' } else { ('0x{0:X}' -f $machine) }
    } catch { $wow = '?' }
    Write-Output ("pid={0,-6} {1,-6} {2}" -f $id, $wow, $p.ProcessName)
}
