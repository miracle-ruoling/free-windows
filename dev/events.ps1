$ErrorActionPreference = 'SilentlyContinue'
$ev = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-3)} -MaxEvents 400
$ev | Where-Object { $_.Message -match 'dock' } | Select-Object -First 12 |
  ForEach-Object { Write-Output ("--- " + $_.TimeCreated + " [" + $_.ProviderName + " id=" + $_.Id + "]"); Write-Output ($_.Message.Substring(0, [Math]::Min(700, $_.Message.Length))) }
Write-Output "== crash dumps =="
Get-ChildItem "$env:LOCALAPPDATA\CrashDumps" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'dock' } | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String
