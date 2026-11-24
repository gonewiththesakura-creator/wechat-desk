$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$controlDir = 'D:\WeChatDesk\control'
$pauseFile = Join-Path $controlDir 'paused'
$statusFile = Join-Path $controlDir 'status.json'
$form = New-Object Windows.Forms.Form
$form.Text = '微信客服'
$form.ClientSize = New-Object Drawing.Size(355,130)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$label = New-Object Windows.Forms.Label
$label.SetBounds(16,14,326,55)
$form.Controls.Add($label)
$toggle = New-Object Windows.Forms.Button
$toggle.SetBounds(16,78,120,32)
$form.Controls.Add($toggle)
$viewer = New-Object Windows.Forms.Button
$viewer.Text = '打开微信画面'
$viewer.SetBounds(150,78,140,32)
$form.Controls.Add($viewer)
function Update-State {
    $paused = Test-Path -LiteralPath $pauseFile
    $toggle.Text = if ($paused) {'恢复接待'} else {'暂停接待'}
    try {
        $s = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $s.checked
        $line = if ($age -gt 12) {'监控程序未更新状态'} elseif ($paused) {'接待已暂停'} else {$s.message}
        $label.Text = "$line`r`n已确认 $($s.confirmed) 条　待核对 $($s.uncertain) 条"
    } catch { $label.Text = '等待独立微信桌面启动' }
}
$toggle.Add_Click({
    if (Test-Path -LiteralPath $pauseFile) {
        Remove-Item -LiteralPath $pauseFile
    } else { [IO.File]::WriteAllText($pauseFile,'paused') }
    Update-State
})
$viewer.Add_Click({
    Start-Process powershell.exe -ArgumentList '-NoProfile','-File','D:\WeChatDesk\setup\open.ps1','-ShowViewer' -WindowStyle Hidden
})
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1800
$timer.Add_Tick({Update-State})
$timer.Start()
Update-State
try { [void]$form.ShowDialog() } finally { $timer.Dispose(); $form.Dispose() }
