param([switch]$Unpin)
$pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$lnk = Join-Path $env:TEMP 'dock_pin_test.lnk'
$sh = New-Object -ComObject WScript.Shell
if (-not $Unpin) {
    $sc = $sh.CreateShortcut($lnk)
    $sc.TargetPath = "$env:WINDIR\System32\notepad.exe"
    $sc.Save()
    Write-Output ("lnk: " + $lnk)
    Write-Output '--- pinned folder BEFORE'
    Get-ChildItem (Join-Path $pinDir '*.lnk') | ForEach-Object { Write-Output ("  " + $_.Name) }
    Write-Output '--- pinning with the undocumented "taskbarpin" verb'
    try {
        $p = Start-Process -FilePath $lnk -Verb taskbarpin -PassThru -ErrorAction Stop
        Write-Output ("  started: " + $p.Id)
    } catch {
        Write-Output ("  FAILED: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds 3
    Write-Output '--- pinned folder AFTER'
    Get-ChildItem (Join-Path $pinDir '*.lnk') | ForEach-Object { Write-Output ("  " + $_.Name) }
} else {
    Write-Output '--- unpinning with "taskbarunpin"'
    try {
        $p = Start-Process -FilePath $lnk -Verb taskbarunpin -PassThru -ErrorAction Stop
        Write-Output ("  started: " + $p.Id)
    } catch {
        Write-Output ("  FAILED: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds 3
    Write-Output '--- pinned folder AFTER unpin'
    Get-ChildItem (Join-Path $pinDir '*.lnk') | ForEach-Object { Write-Output ("  " + $_.Name) }
}
