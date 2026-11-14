$ErrorActionPreference = 'Stop'
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$item = Get-Item $k
Write-Output "---- values ----"
foreach ($n in $item.GetValueNames()) {
    $kind = $item.GetValueKind($n)
    $len = 0
    try { $val = $item.GetValue($n); if ($val -is [byte[]]) { $len = $val.Length } elseif ($val -is [string]) { $len = $val.Length } } catch {}
    Write-Output ("{0,-24} {1,-12} len={2}" -f $n, $kind, $len)
}
Write-Output "---- subkeys ----"
Get-ChildItem $k | Select-Object -ExpandProperty PSChildName

# odd-offset decode of Favorites
$v = $item.GetValue('Favorites')
$s1 = [System.Text.Encoding]::Unicode.GetString($v, 1, $v.Length - 1 - (($v.Length - 1) % 2))
Write-Output "---- odd-offset name probes ----"
foreach ($n in 'Explorer.lnk','Clash','Echo','UU') {
    Write-Output ("{0,-14} at {1}" -f $n, $s1.IndexOf($n))
}
