Add-Type -Namespace Q -Name K -MemberDefinition @'
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
for ($i=0; $i -lt 5; $i++) {
  $l = [Q.K]::GetAsyncKeyState(0x01)
  $r = [Q.K]::GetAsyncKeyState(0x02)
  $p = New-Object Q.K+POINT
  [void][Q.K]::GetCursorPos([ref]$p)
  Write-Output ("L=0x{0:X4} R=0x{1:X4} cursor={2},{3} fg={4}" -f $l, $r, $p.X, $p.Y, [Q.K]::GetForegroundWindow())
  Start-Sleep -Milliseconds 300
}
