$root = 'HKCU:\Control Panel\NotifyIconSettings'
$rows = @()
foreach ($s in Get-ChildItem $root) {
    $p = Get-ItemProperty $s.PSPath
    if (-not $p.IconSnapshot) { continue }
    $b = $p.IconSnapshot
    if ($b.Length -lt 33) { continue }
    # PNG: width/height are big-endian 32-bit at offset 16 and 20
    $w = ($b[16] -shl 24) -bor ($b[17] -shl 16) -bor ($b[18] -shl 8) -bor $b[19]
    $h = ($b[20] -shl 24) -bor ($b[21] -shl 16) -bor ($b[22] -shl 8) -bor $b[23]
    $rows += [pscustomobject]@{ W = $w; H = $h; Bytes = $b.Length; Exe = [System.IO.Path]::GetFileName($p.ExecutablePath) }
}
$rows | Group-Object W, H | ForEach-Object { Write-Output ($_.Name + "  count=" + $_.Count) }
