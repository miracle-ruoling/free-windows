# Ask a running dock to reload dock.ini (the same path the settings panel uses: WM_TIMER 2).
# FindWindow() returns 0 for this class here (UIPI related - the probe is a lower integrity
# process), so the strip handle is looked up with EnumWindows instead.
param([int]$Delay = 800)
Add-Type -Namespace W -Name R -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
public delegate bool EnumProc(IntPtr h, IntPtr lp);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
'@
$found = [IntPtr]::Zero
$cb = [W.R+EnumProc]{ param($h, $lp)
  $sb = New-Object System.Text.StringBuilder 256
  [void][W.R]::GetClassNameW($h, $sb, 256)
  if ($sb.ToString() -eq 'DockStripWindow') { $script:found = $h; return $false }
  return $true }
[void][W.R]::EnumWindows($cb, [IntPtr]::Zero)
if ($found -eq [IntPtr]::Zero) { Write-Output "dock is not running (no DockStripWindow)"; exit 1 }
$ok = [W.R]::PostMessageW($found, 0x0113, [IntPtr]2, [IntPtr]::Zero)   # WM_TIMER, id 2
Write-Output ("posted reload to dock " + $found.ToInt64() + " ok=" + $ok)
Start-Sleep -Milliseconds $Delay
