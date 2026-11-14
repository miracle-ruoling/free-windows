Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr MapViewOfFile(IntPtr h, uint access, uint offHigh, uint offLow, UIntPtr bytes);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool UnmapViewOfFile(IntPtr p);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
'@
$h = [W.K]::OpenFileMapping(0x0004, $false, 'Local\DockTrayBridge_v1')
if ($h -eq [IntPtr]::Zero) { Write-Output 'no mapping'; exit 1 }
$view = [W.K]::MapViewOfFile($h, 0x0004, 0, 0, [UIntPtr]1048576)
if ($view -eq [IntPtr]::Zero) { Write-Output 'map failed'; exit 1 }
$magic = [Runtime.InteropServices.Marshal]::ReadInt32($view, 0)
$ver = [Runtime.InteropServices.Marshal]::ReadInt32($view, 4)
$count = [Runtime.InteropServices.Marshal]::ReadInt32($view, 8)
$cap = [Runtime.InteropServices.Marshal]::ReadInt32($view, 12)
Write-Output ("magic=0x{0:X8} version={1} count={2} capacity={3}" -f $magic, $ver, $count, $cap)
# entry size: 8 + 4*4 + 16 + 256 + 520 = 816
$entrySize = 816
$base = 24
for ($i = 0; $i -lt [Math]::Min($count, 8); $i++) {
    $o = $base + $i * $entrySize
    $hwnd = [Runtime.InteropServices.Marshal]::ReadInt64($view, $o)
    $uid = [Runtime.InteropServices.Marshal]::ReadInt32($view, $o + 8)
    $cb = [Runtime.InteropServices.Marshal]::ReadInt32($view, $o + 12)
    $tip = [Runtime.InteropServices.Marshal]::PtrToStringUni($view + $o + 40, 64)
    Write-Output ("  [{0}] hwnd=0x{1:X} uid={2} cb=0x{3:X} tip='{4}'" -f $i, $hwnd, $uid, $cb, $tip.Trim([char]0))
}
[void][W.K]::UnmapViewOfFile($view)
[void][W.K]::CloseHandle($h)
