try{
    #Get registry install location
    $InstallLocation = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\" -Name InstallLocation
    
    #Check if installed location exists and delete
    if (Test-Path ($InstallLocation)){
        Remove-Item $InstallLocation -Force -Recurse
        Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
        Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False    
        & reg delete "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /f | Out-Null
        & reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" /f | Out-Null

        Write-host "Uninstallation succeeded!" -ForegroundColor Green
        Start-sleep 1
    }
    else {
        Write-host "$InstallLocation not found! Uninstallation failed!" -ForegroundColor Red
    }
}
catch{
    Write-host "`nUninstallation failed! Run as admin ?" -ForegroundColor Red
    Start-sleep 1
}