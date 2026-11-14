param([string]$Exe = 'deepseek', [string]$Out = 't_raise')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
Add-Type -Namespace F -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
'@
function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
if (-not (Wait-Idle 1200 40)) { Write-Output 'user busy'; exit 1 }
if (GridVisible) { [S]::MoveTo(8, 1060); Start-Sleep -Milliseconds 120; [S]::LeftClick(); Start-Sleep -Milliseconds 400 }
$before = (Get-LogLines).Count
if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }
Start-Sleep -Milliseconds 500
$lines = Get-LogLines
$entries = New-Object System.Collections.ArrayList
foreach ($l in $lines[$before..($lines.Count - 1)]) {
  $m = [regex]::Match($l, "tray\[(\d+)\] tip='([^']*)' exe=([^ ]+)")
  if ($m.Success) { [void]$entries.Add([pscustomobject]@{ tip = $m.Groups[2].Value; exe = $m.Groups[3].Value }) }
}
$sorted = @($entries.ToArray())
for ($i = 0; $i -lt $sorted.Count; $i++) {
  for ($j = 0; $j -lt $sorted.Count - 1 - $i; $j++) {
    if ([string]::CompareOrdinal($sorted[$j].tip, $sorted[$j + 1].tip) -gt 0) { $t = $sorted[$j]; $sorted[$j] = $sorted[$j + 1]; $sorted[$j + 1] = $t }
  }
}
$cell = -1
for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].exe.ToLower().Contains($Exe)) { $cell = $i; break } }
if ($cell -lt 0) { Write-Output ("no cell for $Exe"); exit 2 }
$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
[S]::MoveTo($cx, $cy); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 600
Show-State 'menu open'
Shot ($Out + '_1.png')
# now raise some foreign window above our demoted panel, like an app activating itself
[S]::MoveTo(1000, 800)
Start-Sleep -Milliseconds 100
$target = [IntPtr]::Zero
$ppt = Get-Process POWERPNT -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($ppt) { $target = $ppt.MainWindowHandle }
Write-Output ("raising " + $target)
if ($target -ne [IntPtr]::Zero) { [void][F.W]::AllowSetForegroundWindow(-1); [void][F.W]::BringWindowToTop($target); [void][F.W]::SetForegroundWindow($target) }
Start-Sleep -Milliseconds 900
Show-State 'after raising another window'
Shot ($Out + '_2.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 14))..($lines.Count - 1)] | Where-Object { $_ -match 'covered|grid:|focus' } | ForEach-Object { Write-Output ("LOG " + $_) }
