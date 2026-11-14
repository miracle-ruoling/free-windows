$ErrorActionPreference = 'Stop'
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$v = (Get-ItemProperty -Path $k -Name 'Favorites').Favorites
Write-Output ("Favorites bytes = " + $v.Length)

# decode as UTF-16LE and pull out every "*.lnk" token
$s = [System.Text.Encoding]::Unicode.GetString($v)
# non-printable -> '.'
$clean = -join ($s.ToCharArray() | ForEach-Object { if ([int]$_ -lt 32) { '.' } else { $_ } })
Write-Output "---- decoded (dots = control chars) ----"
Write-Output $clean

Write-Output "---- lnk tokens ----"
[regex]::Matches($clean, '[A-Za-z0-9_\.\- \u4e00-\u9fff]+\.lnk') | ForEach-Object { $_.Value } | Sort-Object -Unique

Write-Output "---- pinned folder ----"
$dir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
Get-ChildItem $dir -Filter *.lnk | Select-Object -ExpandProperty Name | Sort-Object
