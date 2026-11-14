param([string]$Src = "dock.cpp", [string]$Exe = "dock.exe")
$ErrorActionPreference = 'Stop'
$msvc = 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231'
$sdk  = 'D:\Windows Kits\10'
$ver  = '10.0.26100.0'
$env:INCLUDE = @(
  "$msvc\include",
  "$sdk\Include\$ver\ucrt", "$sdk\Include\$ver\shared", "$sdk\Include\$ver\um",
  "$sdk\Include\$ver\winrt", "$sdk\Include\$ver\cppwinrt"
) -join ';'
$env:LIB = @("$msvc\lib\x64", "$sdk\Lib\$ver\ucrt\x64", "$sdk\Lib\$ver\um\x64") -join ';'
$env:PATH = "$msvc\bin\Hostx64\x64;" + $env:PATH
Set-Location $PSScriptRoot
& cl.exe /nologo /EHsc /MT /std:c++17 /utf-8 /DUNICODE /D_UNICODE /O2 $Src /link /SUBSYSTEM:WINDOWS /OUT:$Exe user32.lib gdi32.lib shell32.lib shlwapi.lib dwmapi.lib ole32.lib advapi32.lib winmm.lib
if ($LASTEXITCODE -ne 0) { Write-Output "build failed, not deploying"; exit $LASTEXITCODE }
# deploy to a normal folder: processes started from the workspace run at low
# integrity and cannot launch other programs
$install = "$env:LOCALAPPDATA\Programs\Dock"
New-Item -ItemType Directory -Force -Path $install | Out-Null
Copy-Item "$PSScriptRoot\dock.exe" "$install\dock.exe" -Force
if (-not (Test-Path "$install\dock.ini")) { Copy-Item "$PSScriptRoot\dock.ini" "$install\dock.ini" -Force -ErrorAction SilentlyContinue }
$a = (Get-FileHash "$PSScriptRoot\dock.exe").Hash
$b = (Get-FileHash "$install\dock.exe").Hash
if ($a -ne $b) {
  Write-Output "WARNING: deployed copy differs from the build output - is dock.exe running?"
} else {
  Write-Output "deployed to $install"
}
exit $LASTEXITCODE

