param([switch]$Remove)
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'Dock.lnk'
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Dock\dock.exe'
$dir = Join-Path $env:LOCALAPPDATA 'Programs\Dock'

if ($Remove) {
    if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Output "removed $lnk" }
    else { Write-Output 'no shortcut to remove' }
    exit 0
}

if (-not (Test-Path $exe)) { Write-Output "missing exe: $exe"; exit 1 }

$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($lnk)
$s.TargetPath = $exe
$s.WorkingDirectory = $dir
$s.IconLocation = "$exe,0"
$s.Description = 'Dock'
$s.WindowStyle = 1
$s.Save()

$r = $ws.CreateShortcut($lnk)
Write-Output ("created: " + $lnk)
Write-Output ("  target  = " + $r.TargetPath)
Write-Output ("  workdir = " + $r.WorkingDirectory)
Write-Output ("  exists  = " + (Test-Path $lnk))
