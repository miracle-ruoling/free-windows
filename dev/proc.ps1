Get-CimInstance Win32_Process -Filter "Name='Code.exe'" |
  Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine |
  Format-List
