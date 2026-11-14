param([int]$Row = -1, [int]$Col = -1, [int]$Cell = -1, [string]$Out = 'gridrc.png', [int]$Wait = 1200)
# Right-click one grid cell, opening the panel first if needed.
# The chevron is not at a fixed offset (the strip is as wide as its layout needs),
# so scan inwards from the right edge: everything right of the chevron is padding,
# so the first click that opens the grid hits the chevron.
Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
"@
[void][W.U]::SetProcessDPIAware()

$strip = [W.U]::FindWindow("DockStripWindow", [NullString]::Value)
if ($strip -eq [IntPtr]::Zero) { Write-Output 'no strip window'; exit 1 }
$grid = [W.U]::FindWindow("DockGridWindow", [NullString]::Value)
$gridOpen = ($grid -ne [IntPtr]::Zero) -and [W.U]::IsWindowVisible($grid)
Write-Output ("grid open before: " + $gridOpen)

if (-not $gridOpen) {
    $c = New-Object W.U+RECT
    [void][W.U]::GetClientRect($strip, [ref]$c)
    $y = [int]($c.Bottom / 2)
    $opened = $false
    foreach ($n in 40, 56, 72, 88, 104, 120, 136, 152, 168, 184, 200) {
        $x = $c.Right - $n
        $p = New-Object W.U+POINT
        $p.X = $x; $p.Y = $y
        [void][W.U]::ClientToScreen($strip, [ref]$p)
        [void][W.U]::SetCursorPos($p.X, $p.Y)
        Start-Sleep -Milliseconds 450
        $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
        [void][W.U]::SendMessage($strip, 0x0201, [IntPtr]1, $lp)
        Start-Sleep -Milliseconds 60
        [void][W.U]::SendMessage($strip, 0x0202, [IntPtr]0, $lp)
        Start-Sleep -Milliseconds 500
        $grid = [W.U]::FindWindow("DockGridWindow", [NullString]::Value)
        if ($grid -ne [IntPtr]::Zero -and [W.U]::IsWindowVisible($grid)) {
            Write-Output ("opened with chevron at client x=" + $x)
            $opened = $true
            break
        }
    }
    if (-not $opened) { Write-Output 'grid did not open'; exit 1 }
}

$gr = New-Object W.U+RECT
[void][W.U]::GetWindowRect($grid, [ref]$gr)
$gw = $gr.Right - $gr.Left
# the panel is square-ish: derive the column count from its width instead of assuming
$cols = [int](($gw - 28 + 6) / 66)
if ($cols -lt 1) { $cols = 1 }
if ($Cell -eq -2) {
    # just open the panel and screenshot it, do not click any cell
    Add-Type -AssemblyName System.Drawing
    Start-Sleep -Milliseconds 600
    $w0 = [W.U]::GetSystemMetrics(0); $h0 = [W.U]::GetSystemMetrics(1)
    $bmp0 = New-Object System.Drawing.Bitmap $w0, $h0
    $g0 = [System.Drawing.Graphics]::FromImage($bmp0)
    $g0.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w0, $h0))
    $g0.Dispose()
    $bmp0.Save((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp0.Dispose()
    Write-Output ("saved " + $Out + " (no cell click)")
    exit 0
}
if ($Cell -ge 0) { $Row = [int][math]::Floor($Cell / $cols); $Col = $Cell % $cols }
if ($Row -lt 0 -or $Col -lt 0 -or $Col -ge $cols) { Write-Output ("cell out of range (cols=$cols)"); exit 1 }
$cx = $gr.Left + 14 + $Col * 66 + 30
$cy = $gr.Top + 14 + $Row * 66 + 30
Write-Output ("grid at {0},{1} {2}px cols={3} cell r{4}c{5} -> screen {6},{7}" -f $gr.Left, $gr.Top, $gw, $cols, $Row, $Col, $cx, $cy)
[void][W.U]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 450
[W.U]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 110
[W.U]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $Wait

Add-Type -AssemblyName System.Drawing
$w = [W.U]::GetSystemMetrics(0)
$h = [W.U]::GetSystemMetrics(1)
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size $w, $h))
$g.Dispose()
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bmp.Save("$here\$Out", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("saved " + $Out)
