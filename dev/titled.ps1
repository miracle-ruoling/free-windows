$all = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' } | Select-Object Id, ProcessName, MainWindowTitle)
$all | ForEach-Object { Write-Output ($_.Id.ToString() + " " + $_.ProcessName + " [" + $_.MainWindowTitle + "]") }
