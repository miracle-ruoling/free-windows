# Park the real cursor (the strip only renders while the cursor is near it).
param([int]$X = 0, [int]$Y = 0, [int]$WaitMs = 700)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class P { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
                 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[P]::SetProcessDPIAware() | Out-Null
[P]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds $WaitMs
"cursor -> $X,$Y"
