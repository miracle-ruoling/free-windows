param([int]$ProcId = 30208)
$p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
if (-not $p) { Write-Output 'no process'; exit 1 }
$mods = $p.Modules | Where-Object { $_.ModuleName -match 'windhawk|mod_|local@' } | Select-Object -ExpandProperty ModuleName
Write-Output ("modules matching windhawk/mod: " + ($mods -join ', '))
Write-Output ("total modules: " + $p.Modules.Count)
