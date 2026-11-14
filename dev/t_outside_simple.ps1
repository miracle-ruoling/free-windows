param([int]$X = 700, [int]$Y = 700, [int]$Times = 3, [switch]$WithMenu)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')
function GridR() { $g = [S]::ByClass('DockGridWindow'); $r = New-Object S+RECT; [void][S]::GetWindowRect($g, [ref]$r); return $r }
function CellXY($r, $cell) {
  $gw = $r.Right - $r.Left; $cols = [int](($gw - 28 + 6) / 66)
  $row = [int][math]::Floor($cell / $cols); $col = $cell % $cols
  return @(($r.Left + 14 + $col * 66 + 30), ($r.Top + 14 + $row * 66 + 30))
}
for ($i = 1; $i -le $Times; $i++) {
  if (-not (Open-Grid)) { Write-Output ("round " + $i + ": grid did not open"); Start-Sleep -Milliseconds 600; continue }
  Start-Sleep -Milliseconds 300
  if ($WithMenu) {
    $r = GridR; $c = CellXY $r 2
    [S]::MoveTo($c[0], $c[1]); Start-Sleep -Milliseconds 250; [S]::RightClick()
    Start-Sleep -Milliseconds 500
  }
  [S]::MoveTo($X, $Y); Start-Sleep -Milliseconds 200; [S]::LeftClick()
  Start-Sleep -Milliseconds 200
  $grid = [S]::ByClass('DockGridWindow')
  Write-Output ("round $i (menu=" + $WithMenu.IsPresent + "): +200ms gridVisible=" + (($grid -ne [IntPtr]::Zero) -and [S]::IsWindowVisible($grid)))
  Start-Sleep -Milliseconds 800
}
