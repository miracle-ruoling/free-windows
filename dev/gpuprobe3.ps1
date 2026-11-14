$set = Get-Counter -ListSet "GPU Engine" -ErrorAction SilentlyContinue
$set.Paths | Select-Object -First 3
