# Deploy the freshly built dock.exe and bring the dock back up at the same place.
# The dock refuses to run at low integrity (it relaunches itself through the shell), so the
# relaunch goes through explorer.exe on purpose.
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'dock.exe'
$install = "$env:LOCALAPPDATA\Programs\Dock"
$dst = Join-Path $install 'dock.exe'

Add-Type -Namespace D -Name W -MemberDefinition @"
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
"@

$proc = Get-Process dock -ErrorAction SilentlyContinue
if ($proc) {
    $hw = [D.W]::FindWindow('DockStripWindow', $null)
    Write-Output "dock running (pid $($proc.Id)), strip hwnd=$hw - asking it to close"
    if ($hw -ne [IntPtr]::Zero) { [D.W]::PostMessage($hw, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 100
        if (-not (Get-Process dock -ErrorAction SilentlyContinue)) { break }
    }
    if (Get-Process dock -ErrorAction SilentlyContinue) {
        Write-Output "still alive, killing"
        Stop-Process -Name dock -Force
        Start-Sleep -Milliseconds 400
    }
}
Copy-Item $src $dst -Force
$a = (Get-FileHash $src).Hash
$b = (Get-FileHash $dst).Hash
if ($a -ne $b) { Write-Output "WARNING: deployed copy differs"; exit 1 }
Write-Output "deployed $dst"
Start-Process explorer.exe -ArgumentList "`"$dst`""
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 150
    $p = Get-Process dock -ErrorAction SilentlyContinue
    if ($p) { Write-Output "dock back up: pid $($p.Id)"; break }
}
Start-Sleep -Milliseconds 400
$p = Get-Process dock -ErrorAction SilentlyContinue
if (-not $p) { Write-Output "dock did NOT come back"; exit 1 }
$hw = [D.W]::FindWindow('DockStripWindow', $null)
Write-Output "strip hwnd now $hw"
