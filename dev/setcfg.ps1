param([string]$Ini = "$env:LOCALAPPDATA\Programs\Dock\dock.ini", [string]$Set = '')
# Set = "key=value;key=value"
if (-not (Test-Path "$Ini.bak")) { Copy-Item $Ini "$Ini.bak" -Force }
$lines = [System.IO.File]::ReadAllLines($Ini)
$pairs = @{}
foreach ($p in $Set.Split(';')) {
    if ($p.Trim() -eq '') { continue }
    $kv = $p.Split('=', 2)
    $pairs[$kv[0].Trim()] = $kv[1].Trim()
}
$out = New-Object System.Collections.Generic.List[string]
$seen = @{}
foreach ($l in $lines) {
    $t = $l.Trim()
    if ($t.StartsWith('[')) { $out.Add($l); continue }
    $eq = $t.IndexOf('=')
    if ($eq -gt 0) {
        $k = $t.Substring(0, $eq).Trim()
        if ($pairs.ContainsKey($k)) {
            $out.Add("$k=$($pairs[$k])")
            $seen[$k] = $true
            continue
        }
    }
    $out.Add($l)
}
foreach ($k in $pairs.Keys) {
    if (-not $seen.ContainsKey($k)) { $out.Add("$k=$($pairs[$k])") }
}
# no BOM: GetPrivateProfileString treats a BOM as garbage
[System.IO.File]::WriteAllText($Ini, ($out -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $false))
Get-Content $Ini
