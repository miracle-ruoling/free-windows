# 搂3.40 repro: which cell does a press pick, and does a near miss still click?
#
# Everything goes through SendMessage(WM_LBUTTONDOWN/UP) with client coordinates, so the
# physical cursor is never moved and the hover zoom cannot shift the row between the
# measurement and the press. The geometry is read from the dock itself: WM_APP+9 makes it
# log every live cell rect with its live zoom plus the gesture state, so the expectations are
# exact even while a cell is zoomed.
#
# Reads the log from the tail (the newest entry is what we just caused), never by offset -
# the dock appends "\r\n" per entry and an offset drifts.
param([string]$Tag = 'hit')
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'statelib.ps1')

$strip = [S]::ByClass('DockStripWindow')
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no DockStripWindow'; exit 1 }
$cr = New-Object S+RECT
[void][S]::GetClientRect($strip, [ref]$cr)
$W = $cr.Right; $H = $cr.Bottom
Write-Output "strip client ${W}x${H}"

function Press([int]$x, [int]$y, [int]$holdMs = 55) {
  $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
  [void][S]::SendMessage($strip, 0x0201, [IntPtr]1, $lp)
  Start-Sleep -Milliseconds $holdMs
  [void][S]::SendMessage($strip, 0x0202, [IntPtr]0, $lp)
  Start-Sleep -Milliseconds 320
}

# The live cell rects + gesture state, straight from the dock (WM_APP+9 = 0x8009).
function Cells {
  [void][S]::SendMessage($strip, 0x8009, [IntPtr]0, [IntPtr]0)
  Start-Sleep -Milliseconds 250
  $lines = Get-LogLines
  for ($i = $lines.Count - 1; $i -ge 0 -and $i -ge $lines.Count - 8; $i--) {
    if ($lines[$i] -notmatch 'slots:press=(\d+) slot=(-?\d+) drag=(\d+) reorder=(\d+) resize=(\d+) armed=(\d+) hover=(-?\d+) alpha=(\d+) through=(\d+)(.*)$') { continue }
    $state = "press=$($Matches[1]) slot=$($Matches[2]) drag=$($Matches[3]) reorder=$($Matches[4]) resize=$($Matches[5]) armed=$($Matches[6]) hover=$($Matches[7]) alpha=$($Matches[8]) through=$($Matches[9])"
    $list = @()
    foreach ($m in [regex]::Matches($Matches[10], '(\d+):item=(-?\d+) (-?\d+),(-?\d+)-(-?\d+),(-?\d+) sz=(\d+) zoom=([\d.]+)')) {
      $list += [pscustomobject]@{
        i = [int]$m.Groups[1].Value; item = [int]$m.Groups[2].Value
        l = [int]$m.Groups[3].Value; t = [int]$m.Groups[4].Value
        r = [int]$m.Groups[5].Value; b = [int]$m.Groups[6].Value
        sz = [int]$m.Groups[7].Value; zoom = [double]$m.Groups[8].Value
      }
    }
    return [pscustomobject]@{ cells = $list; state = $state }
  }
  return $null
}

$first = Cells
if (-not $first) { Write-Output 'no slot dump - is this the build with the 搂3.40 diagnostics?'; exit 1 }
Write-Output ("state: " + $first.state)
Write-Output ("cells: " + (($first.cells | ForEach-Object { "$($_.i)=$($_.l),$($_.t)-$($_.r),$($_.b) item=$($_.item) z=$($_.zoom)" }) -join ' '))

# What the press turned into: read back from the tail of the log.
function LastResult {
  $lines = Get-LogLines
  $down = '-'; $snap = '-'; $edge = '-'; $click = '-'; $dec = '-'
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $s = $lines[$i]
    if ($s -match 'LBUTTONDOWN at .* slot=(-?\d+) .* miss=(\d+)') {
      $down = "$($Matches[1])/$($Matches[2])"
      break
    }
  }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $s = $lines[$i]
    if ($s -match 'press: slot=(\d+) was (\d+) px outside') { $snap = "$($Matches[1])/$($Matches[2])px" }
    if ($s -match 'resize: press at the edge never moved') { $edge = 'click' }
    if ($s -match 'resize: armed') { $edge = 'resize' }
    if ($s -match 'click slot=(-?\d+)') { $click = $Matches[1] }
    if ($s -match 'click: slot=(\d+) ->') { $dec = 'open' }
    if ($s -match 'click: blank at') { $dec = 'blank' }
    if ($s -match '^..:..:..\.\d\d\d LBUTTONDOWN') { break }   # stop at this press
  }
  return [pscustomobject]@{ down = $down; snap = $snap; edge = $edge; click = $click; dec = $dec }
}

function Test([string]$name, [scriptblock]$pick) {
  $geo = Cells                      # fresh geometry for every press
  if (-not $geo) { Write-Output ("{0,-26} no dump" -f $name); return }
  $pt = & $pick $geo.cells
  Press $pt[0] $pt[1]
  $r = LastResult
  Write-Output ("{0,-26} at {1,4},{2,3}  down={3,-5} snap={4,-8} edge={5,-7} click={6,-3} {7}" -f `
      $name, $pt[0], $pt[1], $r.down, $r.snap, $r.edge, $r.click, $r.dec)
}

$mid = { param($c) $x = $c[3]; @([int](($x.l + $x.r) / 2), [int](($x.t + $x.b) / 2)) }
$gap = { param($c) $x = $c[3]; @([int]($x.r + 3), [int](($x.t + $x.b) / 2)) }
$tail = { param($c) $x = $c[$c.Count - 1]; @([int]($x.r + 6), [int](($x.t + $x.b) / 2)) }
$padY = $H - 4                       # inside the bottom resize band (the last 10 px)
$pad = { param($c) $x = $c[3]; @([int](($x.l + $x.r) / 2), $script:padY) }
$corner = { param($c) @(2, 2) }

Write-Output "`n--- presses (client coordinates) ---"
Write-Output "T1 = a plain click on a cell; T2 = 3 px into the gap right of it; T3 = 6 px past the"
Write-Output "chevron (the 22:24:16 press); T4 = the bottom resize band at the cell's x (22:45:09);"
Write-Output "T5 = 2,2 (a corner: blank + border band)."
Test 'T1 exact centre'      $mid
Test 'T2 3 px into the gap' $gap
Test 'T3 6 px past chevron' $tail
Test 'T4 bottom band'       $pad
Test 'T5 corner 2,2'        $corner
