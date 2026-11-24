# §3.40 with a *real* mouse message flow (mouse_event, like a user click): hover, capture,
# press, release, and the zoom animation all take part. The click matrix in t_click_hit.ps1
# only proves the hit test; this proves the whole path still ends in a launch after the
# "armed, not started" resize change.
param([int]$Cell = 3)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

$strip = [S]::ByClass('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no DockStripWindow'; exit 1 }
if (-not (Wait-Idle 1200 30)) { Write-Output 'user busy'; exit 1 }

function Rect { $r = New-Object S+RECT; [void][S]::GetWindowRect($strip, [ref]$r); return $r }
function Client { $c = New-Object S+RECT; [void][S]::GetClientRect($strip, [ref]$c); return $c }
function CursorTo([int]$x, [int]$y) { [void][S]::SetCursorPos($x, $y) }

$start = New-Object S+POINT
[void][S]::GetCursorPos([ref]$start)

# wake it if it is parked off-screen, then read the *awake* geometry
$r = Rect
if ($r.Top -lt 0 -or $r.Bottom -le 24) {
  CursorTo ([int](($r.Left + $r.Right) / 2)) 2
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 100
    $r = Rect
    if ($r.Top -ge 0 -and $r.Bottom -gt 24) { break }
  }
  Start-Sleep -Milliseconds 500
}
$r = Rect; $c = Client
Write-Output ("strip {0},{1} client {2}x{3}" -f $r.Left, $r.Top, $c.Right, $c.Bottom)

# the base row geometry: cell 0 starts at win.left, cells are icon+gap wide (no zoom at rest)
$cells = @()
$log = Get-LogLines
for ($i = $log.Count - 1; $i -ge 0; $i--) {
  if ($log[$i] -match 'layout: cap=\d+ show=\d+ cells=\d+ scroll=\d+ items=\d+ win=(\d+),(\d+)-(\d+),(\d+) chevron=(\d+),(\d+)-(\d+),(\d+) icon=(\d+)') {
    $wi = [int]$Matches[1]; $wi2 = [int]$Matches[3]; $ic = [int]$Matches[9]
    $gap = [int](($Matches[5] - $wi - 9 * $ic) / 9)   # 9 cells between win.left and chevron.left
    $cells = @{ left = $wi; top = [int]$Matches[2]; right = $wi2; bottom = [int]$Matches[4]; icon = $ic; gap = $gap; chevron = [int]$Matches[5]; chevronR = [int]$Matches[7] }
    break
  }
}
if (-not $cells) { Write-Output 'no layout line'; exit 1 }
Write-Output ("row: {0},{1}-{2},{3} icon={4} gap={5} chevron={6}" -f $cells.left, $cells.top, $cells.right, $cells.bottom, $cells.icon, $cells.gap, $cells.chevron)

function CellX([int]$i) { return [int]($cells.left + $i * ($cells.icon + $cells.gap) + $cells.icon / 2) }
$cy = $cells.top + [int]($cells.icon / 2)

$results = @()
function Run([string]$name, [int]$clientX, [int]$clientY, [int]$settle = 350) {
  # 贴边隐藏: after a click the group may fold away, and a click on the parked strip goes to
  # whatever is behind it (this is how a test "loses" clicks - not a dock bug). Wake it at the
  # top edge first and only click once the window really is on screen at its awake position.
  $awake = $false
  for ($try = 0; $try -lt 3 -and -not $awake; $try++) {
    CursorTo ([int](($r.Left + $r.Right) / 2)) 2
    for ($i = 0; $i -lt 30; $i++) {
      Start-Sleep -Milliseconds 100
      $rr = Rect
      if ($rr.Top -ge 0 -and $rr.Bottom -gt 24) { $awake = $true; break }
    }
  }
  if (-not $awake) { Write-Output ("{0,-28} SKIPPED: the strip did not wake" -f $name); return }
  Start-Sleep -Milliseconds 450
  $before = (Get-LogLines).Count
  CursorTo ($r.Left + $clientX) ($r.Top + $clientY)
  Start-Sleep -Milliseconds $settle
  [S]::LeftClick()
  Start-Sleep -Milliseconds 600
  $got = ''
  foreach ($l in (Get-LogLines | Select-Object -Skip $before)) {
    if ($l -match 'click slot=(-?\d+)') { $got = 'click ' + $Matches[1] }
    if ($l -match 'press: slot=(\d+) was (\d+) px') { $got = "snap $($Matches[1])/$($Matches[2])px " + $got }
    if ($l -match 'resize: press at the edge never moved') { $got = 'edge->' + $got }
    if ($l -match 'activate: (\w[\w ]*)') { $got = $got + ' | ' + $Matches[1] }
    if ($l -match 'minimize: iconicAfter=(\d)') { $got = $got + ' | minimize->' + $Matches[1] }
  }
  $script:results += [pscustomobject]@{ test = $name; got = $got }
  Write-Output ("{0,-28} {1}" -f $name, $got)
}

Run "R1 cell centre" (CellX $Cell) $cy
Run "R2 6 px into the gap" ((CellX $Cell) + [int]($cells.icon / 2) + 6) $cy
Run "R3 bottom pad band" (CellX $Cell) ($c.Bottom - 4)
Run "R4 left pad, above the row" (CellX $Cell) 4

CursorTo $start.X $start.Y
Start-Sleep -Milliseconds 200
Write-Output ("`ncursor restored to {0},{1}" -f $start.X, $start.Y)
