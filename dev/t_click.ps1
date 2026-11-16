# Left-click at a screen point (DPI-aware, no window search). Handy for picking menu items.
#
#   .\t_click.ps1 -X 1280 -Y 85 [-Double]
param([Parameter(Mandatory = $true)] [int]$X, [Parameter(Mandatory = $true)] [int]$Y,
      [switch]$Double, [int]$HoldMs = 60)
Add-Type -Language CSharp @"
using System; using System.Runtime.InteropServices; using System.Threading;
public class Clk {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  public static string Go(int x, int y, bool dbl, int holdMs) {
    SetCursorPos(x, y);
    Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    Thread.Sleep(holdMs);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    if (dbl) {
      Thread.Sleep(80);
      mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
      Thread.Sleep(holdMs);
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
    Thread.Sleep(350);
    return "clicked " + x + "," + y + (dbl ? " (double)" : "");
  }
}
"@
[void][Clk]::SetProcessDpiAwarenessContext([IntPtr](-4))
Write-Output ([Clk]::Go($X, $Y, [bool]$Double, $HoldMs))
