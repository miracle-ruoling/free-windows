param([int]$Tail = 40, [string]$Pattern = 'bake:|paint:|integrity')
$log = "$env:LOCALAPPDATA\Programs\Dock\dock.log"
Get-Content $log | Select-String -Pattern $Pattern | Select-Object -Last $Tail
