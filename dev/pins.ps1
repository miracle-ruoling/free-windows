$dir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
Write-Output ("dir: " + $dir)
$sh = New-Object -ComObject WScript.Shell
Get-ChildItem (Join-Path $dir '*.lnk') | ForEach-Object {
  $l = $sh.CreateShortcut($_.FullName)
  Write-Output ("--- " + $_.Name)
  Write-Output ("    target='" + $l.TargetPath + "' args='" + $l.Arguments + "' workdir='" + $l.WorkingDirectory + "' icon='" + $l.IconLocation + "'")
}
