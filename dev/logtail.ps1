$p = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.log'
$fs = New-Object System.IO.FileStream($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Unicode)
$txt = $sr.ReadToEnd()
$sr.Close(); $fs.Close()
$lines = $txt -split "`r?`n"
$n = $lines.Count
Write-Output ("lines=" + $n)
$lines[([Math]::Max(0, $n-25))..($n-1)] | ForEach-Object { Write-Output $_ }
