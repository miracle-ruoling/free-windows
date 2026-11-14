param([int[]]$Ids = @(3656, 30896, 27172, 4428, 7316))
function ArchOf([string]$path) {
  try {
    $fs = [System.IO.File]::OpenRead($path)
    $br = New-Object System.IO.BinaryReader($fs)
    $fs.Position = 0x3C
    $pe = $br.ReadInt32()
    $fs.Position = $pe + 4
    $m = $br.ReadUInt16()
    $br.Close(); $fs.Close()
    switch ($m) { 0x8664 { 'x64' } 0x14C { 'x86' } 0xAA64 { 'arm64' } default { ('0x{0:X}' -f $m) } }
  } catch { '?' }
}
foreach ($id in $Ids) {
  $p = Get-Process -Id $id -ErrorAction SilentlyContinue
  if (-not $p) { Write-Output ("pid=$id <gone>"); continue }
  $path = $p.Path
  $arch = if ($path) { ArchOf $path } else { '?' }
  $bridge = '?'
  try {
    $mods = $p.Modules
    $hit = $mods | Where-Object { $_.ModuleName -like '*tray-icons*' }
    $bridge = if ($hit) { 'YES' } else { 'no' }
  } catch { $bridge = 'unreadable' }
  Write-Output ("pid={0,-6} {1,-8} {2,-22} bridge={3}  {4}" -f $id, $p.ProcessName, $arch, $bridge, $path)
}
