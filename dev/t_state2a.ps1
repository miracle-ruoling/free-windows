param([string]$Out = 'state2a.png')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

# state 2a: panel open, pointer wanders far away (no click) -> everything must stay
if (-not (Open-Grid)) { Write-Output 'grid did not open'; exit 1 }
Show-State 'after open'
[S]::MoveTo(1850, 1000)
Start-Sleep -Milliseconds 1500
Show-State 'pointer far away'
Shot $Out
Write-Output ('saved ' + $Out)
