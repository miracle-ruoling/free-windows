$root = 'HKCU:\Control Panel\NotifyIconSettings'
$n = 0
foreach ($s in Get-ChildItem $root) {
    $p = Get-ItemProperty $s.PSPath
    if (-not $p.IconSnapshot) { continue }
    $b = $p.IconSnapshot
    $head = ($b[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' '
    Write-Output ("len=" + $b.Length + " head=" + $head + "  exec=" + [System.IO.Path]::GetFileName($p.ExecutablePath))
    $n++
    if ($n -ge 6) { break }
}
