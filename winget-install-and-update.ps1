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

    #Check if Visual C++ 2015-2019 is installed. If not, download and install
    $app = "Microsoft Visual C++ 2019 X64*"
    $path = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -like $app } | Select-Object -Property Displayname, DisplayVersion
    if (!($path)){
        Write-host "MS Visual C++ 2015-2019 is not installed."
        Write-host "Downloading VC_redist.x64.exe..."
        $SourceURL = "https://aka.ms/vs/16/release/VC_redist.x64.exe"
        $Installer = $env:TEMP + "\vscode.exe"
        Invoke-WebRequest $SourceURL -OutFile $Installer
        Write-host "Installing VC_redist.x64.exe..."
        Start-Process -FilePath $Installer -Args "-q" -Wait
        Remove-Item $Installer
    }

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
    Write-host "`nInstallation succeeded!" -ForegroundColor Green
    Start-sleep 5
}
catch{
    Write-host "`nInstallation failed! Run me with admin rights" -ForegroundColor Red
    Start-sleep 5
}