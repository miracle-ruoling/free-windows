Add-Type -Namespace R2 -Name W -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr h, IntPtr r, bool erase);
[DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr hrgn, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
# The stale menu is a compositor leftover: nothing repainted that area. Nudge the desktop
# and the window underneath to redraw it.
$desk = [R2.W]::GetDesktopWindow()
[void][R2.W]::RedrawWindow($desk, [IntPtr]::Zero, [IntPtr]::Zero, 0x0001 -bor 0x0100 -bor 0x0040)
Start-Sleep -Milliseconds 200
$fw = Get-Process DeepSeek\ Harness -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($fw) {
  [void][R2.W]::ShowWindow($fw.MainWindowHandle, 7)   # SW_MINIMIZE
  Start-Sleep -Milliseconds 250
  [void][R2.W]::ShowWindow($fw.MainWindowHandle, 9)   # SW_RESTORE
  [void][R2.W]::SetForegroundWindow($fw.MainWindowHandle)
  Write-Output ("nudged " + $fw.ProcessName)
} else { Write-Output 'deepseek window not found' }
