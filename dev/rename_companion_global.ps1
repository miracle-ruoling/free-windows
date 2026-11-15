# Rename the companion global g_tray -> g_trayBar inside the companions section only
# (the file already has a std::vector<TrayEntry> g_tray for tray icons).
$path = Join-Path 'C:\Users\20979\RP_Projects\fly_bar\dock' 'dock.cpp'
$txt = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))
$lines = $txt -split "`r?`n"

$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($startIdx -lt 0 -and $lines[$i] -match '^// -+ companions$') { $startIdx = $i }
    elseif ($startIdx -ge 0 -and $lines[$i] -match '^// -+ tray icons$') { $endIdx = $i; break }
}
if ($startIdx -lt 0 -or $endIdx -lt 0) { Write-Output "markers not found"; exit 1 }

$count = 0
for ($i = $startIdx; $i -lt $endIdx; $i++) {
    if ($lines[$i] -match '\bg_tray\b') {
        $lines[$i] = $lines[$i] -replace '\bg_tray\b', 'g_trayBar'
        $count++
    }
}
Write-Output ("renamed lines: " + $count + "  (section " + $startIdx + ".." + $endIdx + ")")
$out = ($lines -join "`r`n")
[System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::UTF8.GetBytes($out))
Write-Output "written"
