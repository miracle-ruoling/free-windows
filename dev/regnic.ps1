$root = 'HKCU:\Control Panel\NotifyIconSettings'
$keys = Get-ChildItem $root
Write-Output ("keys: " + $keys.Count)
$qq = $keys | Where-Object {
    $v = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ExecutablePath
    $v -and ($v -like '*QQ.exe*')
}
Write-Output ("QQ keys: " + $qq.Count)
foreach ($k in $qq) {
    Write-Output ("--- " + $k.PSChildName)
    $p = Get-ItemProperty $k.PSPath
    foreach ($n in $p.PSObject.Properties.Name) {
        if ($n -like 'PS*') { continue }
        $val = $p.$n
        if ($val -is [byte[]]) { $val = "<bytes " + $val.Length + ">" }
        Write-Output ("     {0} = {1}" -f $n, $val)
    }
}
