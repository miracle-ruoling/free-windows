Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
for ($i = 0; $i -lt 6; $i++) {
  $p = New-Object W.U+POINT
  [void][W.U]::GetCursorPos([ref]$p)
  Write-Output ("cursor " + $p.X + "," + $p.Y)
  Start-Sleep -Milliseconds 500
}
$p2 = New-Object W.U+POINT
$ok = [W.U]::SetCursorPos(1000, 400)
Start-Sleep -Milliseconds 200
[void][W.U]::GetCursorPos([ref]$p2)
Write-Output ("set(1000,400) ok=" + $ok + " now=" + $p2.X + "," + $p2.Y)
