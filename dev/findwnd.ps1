param([string]$Cls = "DockStripWindow")
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string win);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
$h = [W.U]::FindWindow($Cls, $null)
if ($h -eq [IntPtr]::Zero) { Write-Output ("no window of class " + $Cls) } else {
  $pid2 = 0
  [void][W.U]::GetWindowThreadProcessId($h, [ref]$pid2)
  $r = New-Object W.U+RECT
  [void][W.U]::GetWindowRect($h, [ref]$r)
  Write-Output ("hwnd=" + $h + " pid=" + $pid2 + " rect=" + $r.Left + "," + $r.Top + " " + ($r.Right-$r.Left) + "x" + ($r.Bottom-$r.Top))
}
