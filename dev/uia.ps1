Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$t0 = Get-Date
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
$dt = ((Get-Date) - $t0).TotalMilliseconds
Write-Output ("buttons found: " + $all.Count + "  in " + [int]$dt + " ms")
$names = @()
foreach ($e in $all) {
    $n = $e.Current.Name
    if ($n) { $names += $n }
}
Write-Output ("named: " + $names.Count)
$names | Select-Object -First 40 | ForEach-Object { Write-Output ("  " + $_) }
