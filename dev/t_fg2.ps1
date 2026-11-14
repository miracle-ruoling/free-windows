param([string]$Out = 't_fg2')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
Add-Type -Namespace F -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
'@
function GridVisible() {
  $g = [S]::ByClass('DockGridWindow')
  return (($g -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($g))
}
# 1) the panel must already be open (run t_fgcase first, or open it here)
if (-not (GridVisible)) { if (-not (Open-Grid)) { Write-Output 'no grid'; exit 1 }; Start-Sleep -Milliseconds 400 }
# 2) make the app itself the foreground window — this is the user's case
$target = [IntPtr]::Zero
$p = Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($p) { $target = $p.MainWindowHandle }
if ($target -eq [IntPtr]::Zero) { Write-Output 'deepseek window not found'; exit 2 }
[void][F.W]::AllowSetForegroundWindow(-1)
[void][F.W]::BringWindowToTop($target)
[void][F.W]::SetForegroundWindow($target)
Start-Sleep -Milliseconds 500
Show-State 'app in front, panel open'
# 3) right click the app's own tray icon in the panel
$g = [S]::ByClass('DockGridWindow')
$r = New-Object S+RECT
[void][S]::GetWindowRect($g, [ref]$r)
$lines = Get-LogLines
$entries = New-Object System.Collections.ArrayList
$start = [Math]::Max(0, $lines.Count - 400)
foreach ($l in $lines[$start..($lines.Count - 1)]) {
  $m = [regex]::Match($l, "tray\[(\d+)\] tip='([^']*)' exe=([^ ]+)")
  if ($m.Success) { [void]$entries.Add([pscustomobject]@{ tip = $m.Groups[2].Value; exe = $m.Groups[3].Value }) }
}
# use the last block only
while ($entries.Count -gt 0) { break }
$sorted = @($entries.ToArray())
for ($i = 0; $i -lt $sorted.Count; $i++) {
  for ($j = 0; $j -lt $sorted.Count - 1 - $i; $j++) {
    if ([string]::CompareOrdinal($sorted[$j].tip, $sorted[$j + 1].tip) -gt 0) { $t = $sorted[$j]; $sorted[$j] = $sorted[$j + 1]; $sorted[$j + 1] = $t }
  }
}
$cell = -1
for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].exe.ToLower().Contains('deepseek')) { $cell = $i; break } }
if ($cell -lt 0) { Write-Output 'no deepseek cell'; exit 3 }
$gw = $r.Right - $r.Left
$cols = [int](($gw - 28 + 6) / 66)
$row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
$cx = $r.Left + 14 + $col * 66 + 30
$cy = $r.Top + 14 + $row * 66 + 30
Write-Output ("cell $cell -> $cx,$cy")
[S]::MoveTo($cx, $cy); Start-Sleep -Milliseconds 250; [S]::RightClick()
Start-Sleep -Milliseconds 800
Show-State 'after right click (app was in front)'
Shot ($Out + '_1.png')
$lines = Get-LogLines
$lines[([Math]::Max(0, $lines.Count - 10))..($lines.Count - 1)] | Where-Object { $_ -match 'tray:|grid:|focus|lifting|covered' } | ForEach-Object { Write-Output ("LOG " + $_) }
