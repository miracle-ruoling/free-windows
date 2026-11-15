# Filter the dock log (it is open for writing, so read with a shared handle).
param([string]$Pattern = '.', [int]$Last = 40)
$p = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd()
$sr.Close(); $fs.Close()
$hits = ($txt -split "`r?`n") | Where-Object { $_ -match $Pattern }
Write-Output ("matches=" + $hits.Count)
$hits | Select-Object -Last $Last
