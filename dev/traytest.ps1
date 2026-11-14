param([string]$Mark = 'traymark.txt')
# Synthetic tray icon: a real Shell_NotifyIcon registration with a real context menu,
# so the dock can forward a right click to it and we can pick an item safely.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mark = Join-Path $here $Mark
Set-Content -Path $mark -Value ("started " + (Get-Date -Format 'HH:mm:ss.fff'))

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = 'Minimized'
$form.FormBorderStyle = 'None'
$form.Opacity = 0
$form.Text = 'TrayTest'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$item1 = $menu.Items.Add('测试项 1')
$item1.add_Click({
  Add-Content -Path $mark -Value ("item1 clicked " + (Get-Date -Format 'HH:mm:ss.fff'))
})
$item2 = $menu.Items.Add('测试项 2')
$item2.add_Click({
  Add-Content -Path $mark -Value ("item2 clicked " + (Get-Date -Format 'HH:mm:ss.fff'))
})
$null = $menu.Items.Add('-')
$itemQ = $menu.Items.Add('退出')
$itemQ.add_Click({
  Add-Content -Path $mark -Value ("quit clicked " + (Get-Date -Format 'HH:mm:ss.fff'))
  [System.Windows.Forms.Application]::Exit()
})

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.Text = 'TrayTest'
$icon.ContextMenuStrip = $menu
$icon.add_MouseClick({
  param($sender, $e)
  Add-Content -Path $mark -Value ("mouse " + $e.Button.ToString() + " " + (Get-Date -Format 'HH:mm:ss.fff'))
})
$icon.Visible = $true
Add-Content -Path $mark -Value ("icon visible " + (Get-Date -Format 'HH:mm:ss.fff'))

$ctx = New-Object System.Windows.Forms.ApplicationContext
$null = $form
[System.Windows.Forms.Application]::Run($ctx)
Add-Content -Path $mark -Value ("exited " + (Get-Date -Format 'HH:mm:ss.fff'))
