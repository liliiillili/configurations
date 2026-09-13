$exe = "C:\Windows\System32\wsl.exe"
$arg = "-d Ubuntu-24.04 -u root --exec /usr/bin/sleep infinity"
$me  = "$env:USERDOMAIN\$env:USERNAME"

$a = New-ScheduledTaskAction -Execute $exe -Argument $arg
$t = @( (New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn -User $me) )
$p = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName "WSL Keepalive" -Action $a -Trigger $t -Principal $p -Settings $s -Force
Start-ScheduledTask -TaskName "WSL Keepalive"

Get-ScheduledTask -TaskName "WSL Keepalive" | Get-ScheduledTaskInfo
wsl -l -v
