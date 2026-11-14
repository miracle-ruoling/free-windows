$ErrorActionPreference = 'Stop'
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$v = (Get-ItemProperty -Path $k -Name 'Favorites').Favorites
$s = [System.Text.Encoding]::Unicode.GetString($v)
Write-Output ("wide chars = " + $s.Length)

Write-Output "---- every .lnk occurrence, with preceding run ----"
$idx = 0
while (($idx = $s.IndexOf('.lnk', $idx)) -ge 0) {
    $st = [Math]::Max(0, $idx - 60)
    $frag = $s.Substring($st, $idx - $st + 4)
    $frag = -join ($frag.ToCharArray() | ForEach-Object { if ([int]$_ -lt 32) { '|' } else { $_ } })
    Write-Output ("@" + $idx + "  " + $frag)
    $idx += 4
}

Write-Output "---- name probes ----"
foreach ($n in 'File Explorer','Clash','EchoMusic','QQ','UU','Edge','Visual Studio') {
    $p = $s.IndexOf($n)
    Write-Output ("{0,-16} at {1}" -f $n, $p)
}
