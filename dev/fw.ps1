Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
'@
$h1 = [W.U]::FindWindow("DockStripWindow", $null)
Write-Output ("FindWindow null name -> " + $h1 + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
$h2 = [W.U]::FindWindow("DockStripWindow", "")
Write-Output ("FindWindow empty name -> " + $h2)
$h3 = [W.U]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, "DockStripWindow", $null)
Write-Output ("FindWindowEx -> " + $h3)
$h4 = [W.U]::FindWindow("DockGridWindow", $null)
Write-Output ("grid -> " + $h4)
