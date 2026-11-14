$ErrorActionPreference = 'Stop'
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
$v = (Get-Item $k).GetValue('Favorites')
$even = [System.Text.Encoding]::Unicode.GetString($v, 0, $v.Length - ($v.Length % 2))
$oddLen = $v.Length - 1
$odd = [System.Text.Encoding]::Unicode.GetString($v, 1, $oddLen - ($oddLen % 2))

function Frag([string]$s, [int]$i) {
  $st = [Math]::Max(0, $i - 70)
  $f = $s.Substring($st, $i - $st + 4)
  return (-join ($f.ToCharArray() | ForEach-Object { if ([int]$_ -lt 32) { '|' } else { $_ } }))
}

foreach ($pair in @(@('even',$even), @('odd',$odd))) {
  $tag = $pair[0]; $s = $pair[1]
  Write-Output "==== $tag alignment (len $($s.Length)) ===="
  $i = 0
  while (($i = $s.IndexOf('.lnk', $i)) -ge 0) {
    Write-Output ("@" + $i + "  " + (Frag $s $i))
    $i += 4
  }
}

Write-Output "==== folder lnks vs blob ===="
$dir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
foreach ($f in (Get-ChildItem $dir -Filter *.lnk | Sort-Object Name)) {
  $n = $f.BaseName
  $inEven = ($even.Contains($n + '.lnk'))
  $inOdd  = ($odd.Contains($n + '.lnk'))
  Write-Output ("{0,-16} even={1,-5} odd={2}" -f $n, $inEven, $inOdd)
}
