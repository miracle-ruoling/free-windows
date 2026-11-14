param([switch]$Start)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$old = @(Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'DockBlurTest' })
foreach ($p in $old) { try { $p.Kill() } catch {} }
Write-Output ("killed " + $old.Count + " backdrop(s)")
if ($Start) {
    Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$here\bgtest.ps1")
    Start-Sleep -Milliseconds 1500
    $new = @(Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'DockBlurTest' })
    Write-Output ("started " + $new.Count + " backdrop(s)")
}
