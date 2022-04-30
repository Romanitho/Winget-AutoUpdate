<#
.SYNOPSIS
Configure Winget to daily update installed apps.

.DESCRIPTION
Install powershell scripts and scheduled task to daily run Winget upgrade and notify connected users.
Possible to exclude apps from auto-update
https://github.com/Romanitho/Winget-AutoUpdate

.PARAMETER Silent
Install Winget-AutoUpdate and prerequisites silently

.PARAMETER WingetUpdatePath
Specify Winget-AutoUpdate installation localtion. Default: C:\ProgramData\Winget-AutoUpdate\

.PARAMETER DoNotUpdate
Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation.

.PARAMETER DisableWAUAutoUpdate
Disable Winget-AutoUpdate update checking. By default, WAU auto update if new version is available on Github.

.PARAMETER UseWhiteList
Use White List instead of Black List. This setting will not create the "exclude_apps.txt" but "include_apps.txt"

.PARAMETER Uninstall
Remove scheduled tasks and scripts.

.PARAMETER NotificationLevel
Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

.PARAMETER UpdatesAtLogon
Set WAU to run at user logon.

.PARAMETER UpdatesInterval
Specify the update frequency: Daily (Default), Weekly, Biweekly or Monthly.

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -DoNotUpdate

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -UseWhiteList

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -UpdatesAtLogon -UpdatesInterval Weekly

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)] [Alias('S')] [Switch] $Silent = $false,
    [Parameter(Mandatory=$False)] [Alias('Path')] [String] $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate",
    [Parameter(Mandatory=$False)] [Switch] $DoNotUpdate = $false,
    [Parameter(Mandatory=$False)] [Switch] $DisableWAUAutoUpdate = $false,
    [Parameter(Mandatory=$False)] [Switch] $Uninstall = $false,
    [Parameter(Mandatory=$False)] [Switch] $UseWhiteList = $false,
    [Parameter(Mandatory=$False)] [ValidateSet("Full","SuccessOnly","None")] [String] $NotificationLevel = "Full",
    [Parameter(Mandatory=$False)] [Switch] $UpdatesAtLogon = $false,
    [Parameter(Mandatory=$False)] [ValidateSet("Daily","Weekly","BiWeekly","Monthly")] [String] $UpdatesInterval = "Daily"
)


<# FUNCTIONS #>

function Install-Prerequisites{
    #Check if Visual C++ 2019 or 2022 installed
    $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
    $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
    $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022}
    
    #If not installed, ask for installation
    if (!($path)){
        #If -silent option, force installation
        if ($Silent){
            $InstallApp = 1
        }
        else{
            #Ask for installation
            $MsgBoxTitle = "Winget Prerequisites"
            $MsgBoxContent = "Microsoft Visual C++ 2015-2022 is required. Would you like to install it?"
            $MsgBoxTimeOut = 60
            $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent,$MsgBoxTimeOut,$MsgBoxTitle,4+32)
            if ($MsgBoxReturn -ne 7) {
                $InstallApp = 1
            }
            else {
                $InstallApp = 0
            }
        }
        #Install if approved
        if ($InstallApp -eq 1){
            try{
                if((Get-CimInStance Win32_OperatingSystem).OSArchitecture -like "*64*"){
                    $OSArch = "x64"
                }
                else{
                    $OSArch = "x86"
                }
                Write-host "Downloading VC_redist.$OSArch.exe..."
                $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
                $Installer = $WingetUpdatePath + "\VC_redist.$OSArch.exe"
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest $SourceURL -OutFile (New-Item -Path $Installer -Force)
                Write-host "Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
                Remove-Item $Installer -ErrorAction Ignore
                Write-host "MS Visual C++ 2015-2022 installed successfully" -ForegroundColor Green
            }
            catch{
                Write-host "MS Visual C++ 2015-2022 installation failed." -ForegroundColor Red
                Start-Sleep 3
            }
        }
        else{
            Write-host "MS Visual C++ 2015-2022 wil not be installed." -ForegroundColor Magenta
        }
    }
    else{
        Write-Host "Prerequisites checked. OK" -ForegroundColor Green
    }
}

function Install-WinGet{

    #Check Package Install
    Write-Host "Checking if Winget is installed" -ForegroundColor Yellow
    $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "Microsoft.DesktopAppInstaller"}
    If([Version]$TestWinGet.Version -gt "2022.213.0.0") {

        Write-Host "WinGet is Installed" -ForegroundColor Green
    
    }
    Else{

        #Download WinGet MSIXBundle
        Write-Host "Not installed. Downloading WinGet..."
        $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v1.3.431/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WebClient=New-Object System.Net.WebClient
        $WebClient.DownloadFile($WinGetURL, "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

        #Install WinGet MSIXBundle
        try{
            Write-Host "Installing MSIXBundle for App Installer..."
            Add-AppxProvisionedPackage -Online -PackagePath "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense
            Write-Host "Installed MSIXBundle for App Installer" -ForegroundColor Green
        }
        catch{
            Write-Host "Failed to intall MSIXBundle for App Installer..." -ForegroundColor Red
        }
    
        #Remove WinGet MSIXBundle
        Remove-Item -Path "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue

    }

}

function Install-WingetAutoUpdate{
    try{
        #Copy files to location
        if (!(Test-Path $WingetUpdatePath)){
            New-Item -ItemType Directory -Force -Path $WingetUpdatePath
        }
        Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
        
        #White List or Black List apps
        if ($UseWhiteList){
            if (Test-Path "$PSScriptRoot\included_apps.txt"){
                Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else{
                New-Item -Path $WingetUpdatePath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue
            }
        }
        else {
            Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Set dummy regkeys for notification name and icon
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Application Update" /f | Out-Null
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f | Out-Null

        # Settings for the scheduled task for Updates
        $taskAction = New-ScheduledTaskAction –Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WingetUpdatePath)\winget-upgrade.ps1`""
        $taskTriggers = @()
        if ($UpdatesAtLogon){
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
        if ($UpdatesInterval -eq "Daily"){
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At 6AM
        }
        elseif ($UpdatesInterval -eq "Weekly"){
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At 6AM -DaysOfWeek 2
        }
        elseif ($UpdatesInterval -eq "BiWeekly"){
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At 6AM -DaysOfWeek 2 -WeeksInterval 2
        }
        elseif ($UpdatesInterval -eq "Monthly"){
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At 6AM -DaysOfWeek 2 -WeeksInterval 4
        }
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTriggers
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction –Execute "wscript.exe" -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-notify.ps1`"`""
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -InputObject $task -Force | Out-Null

        # Install config file
        [xml]$ConfigXML = @"
<?xml version="1.0"?>
<app>
    <WAUautoupdate>$(!($DisableWAUAutoUpdate))</WAUautoupdate>
    <WAUprerelease>False</WAUprerelease>
    <UseWAUWhiteList>$UseWhiteList</UseWAUWhiteList>
    <NotificationLevel>$NotificationLevel</NotificationLevel>
</app>
"@
        $ConfigXML.Save("$WingetUpdatePath\config\config.xml")

        Write-host "`n WAU Installation succeeded!" -ForegroundColor Green
        Start-sleep 1
        
        #Run Winget ?
        Start-WingetAutoUpdate
    }
    catch{
        Write-host "`n WAU Installation failed! Run me with admin rights" -ForegroundColor Red
        Start-sleep 1
        return $False
    }
}

function Uninstall-WingetAutoUpdate{
    try{
        #Check if installed location exists and delete
        if (Test-Path ($WingetUpdatePath)){
            Remove-Item $WingetUpdatePath -Force -Recurse
            Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False    
            & reg delete "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /f | Out-Null
    
            Write-host "Uninstallation succeeded!" -ForegroundColor Green
            Start-sleep 1
        }
        else {
            Write-host "$WingetUpdatePath not found! Uninstallation failed!" -ForegroundColor Red
        }
    }
    catch{
        Write-host "`nUninstallation failed! Run as admin ?" -ForegroundColor Red
        Start-sleep 1
    }
}

function Start-WingetAutoUpdate{
    #If -DoNotUpdate is true, skip.
    if (!($DoNotUpdate)){
            #If -Silent, run Winget-AutoUpdate now
            if ($Silent){
                $RunWinget = 1
            }
            #Ask for WingetAutoUpdate
            else{
                $MsgBoxTitle = "Winget-AutoUpdate"
                $MsgBoxContent = "Would you like to run Winget-AutoUpdate now?"
                $MsgBoxTimeOut = 60
                $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent,$MsgBoxTimeOut,$MsgBoxTitle,4+32)
                if ($MsgBoxReturn -ne 7) {
                    $RunWinget = 1
                }
                else {
                    $RunWinget = 0
                }
            }
        if ($RunWinget -eq 1){
            try{
                Write-host "Running Winget-AutoUpdate..." -ForegroundColor Yellow
                Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
                while ((Get-ScheduledTask -TaskName "Winget-AutoUpdate").State -ne  'Ready') {
                    Start-Sleep 1
                }
            }
            catch{
                Write-host "Failed to run Winget-AutoUpdate..." -ForegroundColor Red
            }
        }
    }
    else{
        Write-host "Skip running Winget-AutoUpdate"
    }
}


<# MAIN #>

Write-Host "`n"
Write-Host "`t###################################"
Write-Host "`t#                                 #"
Write-Host "`t#        Winget AutoUpdate        #"
Write-Host "`t#                                 #"
Write-Host "`t###################################"
Write-Host "`n"

if (!$Uninstall){
    Write-host "Installing WAU to $WingetUpdatePath\"
    Install-Prerequisites
    Install-WinGet
    Install-WingetAutoUpdate
}
else {
    Write-Host "Uninstall WAU"
    Uninstall-WingetAutoUpdate
}

Write-host "End of process."

if (!$Silent) {
    Timeout 10
}
