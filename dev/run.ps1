$install = Join-Path $env:LOCALAPPDATA 'Programs\Dock'
Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400
Start-Process -FilePath (Join-Path $install 'dock.exe') -WorkingDirectory $install
Start-Sleep -Seconds 3
Get-Process dock -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, MainWindowHandle | Format-Table -AutoSize | Out-String
Get-Content (Join-Path $install 'dock.log') -TotalCount 14
