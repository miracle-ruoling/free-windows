# High-contrast test backdrop: maximised white window, black stripes and huge
# black text. If the dock's glass is really blurring, this becomes mush.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DockBlurTest'
$form.WindowState = 'Maximized'
$form.FormBorderStyle = 'None'
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::White

$form.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    $g.Clear([System.Drawing.Color]::White)
    # thick black diagonal stripes across the whole screen
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 26
    for ($x = -$h; $x -lt $w + $h; $x += 120) {
        $g.DrawLine($pen, $x, 0, $x + $h, $h)
    }
    $pen.Dispose()
    # big lettering right under where the dock sits
    $font = New-Object System.Drawing.Font 'Segoe UI', 64, ([System.Drawing.FontStyle]::Bold)
    $br = [System.Drawing.Brushes]::Black
    $g.DrawString('BLUR TEST 0123456789', $font, $br, 240, 30)
    $g.DrawString('THE QUICK BROWN FOX', $font, $br, 240, 120)
    $font.Dispose()
    $g.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, 8, $h)
})

# No repaint timer on purpose: invalidating cleared the window to white, and
# PrintWindow then caught a blank frame instead of the stripes.

[System.Windows.Forms.Application]::Run($form)
