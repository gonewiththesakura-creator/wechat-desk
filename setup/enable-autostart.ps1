$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath 'D:\WeChatDesk\desktop-installed.txt')) { throw '请先完成安装。' }
$account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$program = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -Command "& $env:SystemRoot\System32\wsl.exe -d WeChatDesk -u wxdesk --exec /bin/bash /mnt/d/WeChatDesk/setup/keeper.sh; exit $LASTEXITCODE"'
$action = New-ScheduledTaskAction -Execute $program -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'WeChatDesk Reception' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Start-ScheduledTask -TaskName 'WeChatDesk Reception'
