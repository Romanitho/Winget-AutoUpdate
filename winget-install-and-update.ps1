#Create winget-update folder and content structure
$WingetUpdatePath = "$env:ProgramData\winget-update"
Write-host "Instaling to $WingetUpdatePath\"

try{
    #Copy files to location
    if (!(Test-Path $WingetUpdatePath)){
        New-Item -ItemType Directory -Force -Path $WingetUpdatePath
    }
    Copy-Item -Path "$PSScriptRoot\winget-update\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue

    # Set dummy regkeys for notification name and icon
    & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Application Update" /f | Out-Null
    & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f | Out-Null

    # Settings for the scheduled task for Updates
    $taskAction = New-ScheduledTaskAction –Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$($WingetUpdatePath)\winget-upgrade.ps1`""
    $taskTrigger1 = New-ScheduledTaskTrigger -AtLogOn
    $taskTrigger2 = New-ScheduledTaskTrigger  -Daily -At 6AM
    $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

    # Set up the task, and register it
    $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger2,$taskTrigger1
    Register-ScheduledTask -TaskName 'Winget Update' -InputObject $task -Force

    # Settings for the scheduled task for Notifications
    $taskAction = New-ScheduledTaskAction –Execute "wscript.exe" -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-notify.ps1`"`""
    $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
    $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00

    # Set up the task, and register it
    $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
    Register-ScheduledTask -TaskName 'Winget Update Notify' -InputObject $task -Force

    # Run Winget
    Get-ScheduledTask -TaskName "Winget Update" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
    Write-host "Installation succeeded!" -ForegroundColor Green
    Start-sleep 5
}
catch{
    Write-host "Installation failed! Run me with admin rights" -ForegroundColor Red
    Start-sleep 5
}