Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetMonitorInfo(int mi, IntPtr i);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cls, string win);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
"@
$h = [W.U]::FindWindow("Shell_TrayWnd", $null)
$r = New-Object W.U+RECT
[void][W.U]::GetWindowRect($h, [ref]$r)
$mon = [System.Windows.Forms.Screen]::PrimaryScreen
Write-Output ("Shell_TrayWnd hwnd=" + $h)
Write-Output ("rect = " + $r.Left + "," + $r.Top + " - " + $r.Right + "," + $r.Bottom + "  visible=" + [W.U]::IsWindowVisible($h))
Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Output ("primary screen = " + $b.Width + "x" + $b.Height)
