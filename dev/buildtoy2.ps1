param([string]$Src = "acrylic_test.cpp", [string]$Exe = "acrylic_test.exe")
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
& cl.exe /nologo /EHsc /MT /std:c++17 /utf-8 /DUNICODE /D_UNICODE /O2 $Src `
    /link /SUBSYSTEM:CONSOLE /OUT:$Exe user32.lib gdi32.lib dwmapi.lib
exit $LASTEXITCODE
