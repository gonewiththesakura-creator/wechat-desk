param([switch]$ShowViewer)
$ErrorActionPreference = 'Stop'
$wsl = "$env:SystemRoot\System32\wsl.exe"
$port = 16883
$service = 'http://127.0.0.1:16883'
$null = & $wsl -d WeChatDesk -u wxdesk -- test -x /usr/local/bin/wechat-desk
if ($LASTEXITCODE) { throw '请先完成独立微信桌面的安装。' }
$viewer = Start-Process -FilePath $wsl -ArgumentList '-d','WeChatDesk','-u','wxdesk','--','/usr/local/bin/wechat-desk' -WindowStyle Hidden -PassThru
$uidText = (& $wsl -d WeChatDesk -u wxdesk -- id -u | Out-String).Trim()
if ($uidText -notmatch '^\d+$') { throw '无法读取独立桌面状态。' }
$keyFile = "/tmp/wxdesk-$uidText/viewer-key"
$up = $false
for ($i=0;$i -lt 45;$i++) {
    try {
        $reply = Invoke-WebRequest "$service/vnc.html" -UseBasicParsing -TimeoutSec 2
        if ($reply.StatusCode -eq 200 -and $reply.Content -match 'noVNC') { $up=$true; break }
    } catch { }
    Start-Sleep -Seconds 1
}
if (!$up) { throw '本机小窗未能连接到独立桌面。请检查 WSL 和本机端口 16883。' }
if (!$ShowViewer) {
    & "$PSScriptRoot\panel.ps1"
    return
}
$key = (& $wsl -d WeChatDesk -u wxdesk -- cat $keyFile | Out-String).Trim()
if ($key -notmatch '^[0-9a-zA-Z]{8}$') { throw '本机查看密码尚未就绪。' }
$url = "$service/vnc.html?autoconnect=true&resize=scale"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object {Test-Path $_} | Select-Object -First 1
if ($edge) {Start-Process -FilePath $edge -ArgumentList "--app=$url",'--window-size=850,580'} else {Start-Process $url}
Add-Type -AssemblyName System.Windows.Forms
[void][Windows.Forms.MessageBox]::Show("小窗提示连接密码时，请输入 $key 。这仅用于查看本机的虚拟桌面。","微信独立桌面")
