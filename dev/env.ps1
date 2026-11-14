Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Output ("screen: " + $b.Width + "x" + $b.Height)
$p = Get-Process DockBlurTest -ErrorAction SilentlyContinue
if ($p) { Write-Output ("bgtest pid=" + $p.Id + " title=" + $p.MainWindowTitle) } else { Write-Output 'bgtest: NOT RUNNING' }
$d = Get-Process dock -ErrorAction SilentlyContinue
if ($d) { Write-Output ("dock pid=" + $d.Id) } else { Write-Output 'dock: not running' }
