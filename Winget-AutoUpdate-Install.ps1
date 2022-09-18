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

.PARAMETER NoClean
Keep critical files when installing/uninstalling

.PARAMETER NotificationLevel
Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

.PARAMETER UpdatesAtLogon
Set WAU to run at user logon.

.PARAMETER UpdatesInterval
Specify the update frequency: Daily (Default), Weekly, Biweekly or Monthly.

.PARAMETER RunOnMetered
Run WAU on metered connection. Default No.

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -DoNotUpdate

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -UseWhiteList

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -UpdatesAtLogon -UpdatesInterval Weekly

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -Uninstall -NoClean

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $False)] [Alias('S')] [Switch] $Silent = $false,
    [Parameter(Mandatory = $False)] [Alias('Path')] [String] $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate",
    [Parameter(Mandatory = $False)] [Alias('List')] [String] $ListPath = $WingetUpdatePath,
    [Parameter(Mandatory = $False)] [Switch] $DoNotUpdate = $false,
    [Parameter(Mandatory = $False)] [Switch] $DisableWAUAutoUpdate = $false,
    [Parameter(Mandatory = $False)] [Switch] $RunOnMetered = $false,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall = $false,
    [Parameter(Mandatory = $False)] [Switch] $NoClean = $false,
    [Parameter(Mandatory = $False)] [Switch] $UseWhiteList = $false,
    [Parameter(Mandatory = $False)] [ValidateSet("Full", "SuccessOnly", "None")] [String] $NotificationLevel = "Full",
    [Parameter(Mandatory = $False)] [Switch] $UpdatesAtLogon = $false,
    [Parameter(Mandatory = $False)] [ValidateSet("Daily", "Weekly", "BiWeekly", "Monthly")] [String] $UpdatesInterval = "Daily"
)

<# APP INFO #>

$WAUVersion = "1.14.2"

<# FUNCTIONS #>

function Install-Prerequisites {

    Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow
    
    #Check if Visual C++ 2019 or 2022 installed
    $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
    $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
    $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022 }
    
    #If not installed, ask for installation
    if (!($path)) {
        #If -silent option, force installation
        if ($Silent) {
            $InstallApp = 1
        }
        else {
            #Ask for installation
            $MsgBoxTitle = "Winget Prerequisites"
            $MsgBoxContent = "Microsoft Visual C++ 2015-2022 is required. Would you like to install it?"
            $MsgBoxTimeOut = 60
            $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent, $MsgBoxTimeOut, $MsgBoxTitle, 4 + 32)
            if ($MsgBoxReturn -ne 7) {
                $InstallApp = 1
            }
            else {
                $InstallApp = 0
            }
        }
        #Install if approved
        if ($InstallApp -eq 1) {
            try {
                if ((Get-CimInStance Win32_OperatingSystem).OSArchitecture -like "*64*") {
                    $OSArch = "x64"
                }
                else {
                    $OSArch = "x86"
                }
                Write-host "-> Downloading VC_redist.$OSArch.exe..."
                $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
                $Installer = $WingetUpdatePath + "\VC_redist.$OSArch.exe"
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest $SourceURL -OutFile (New-Item -Path $Installer -Force)
                Write-host "-> Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
                Remove-Item $Installer -ErrorAction Ignore
                Write-host "-> MS Visual C++ 2015-2022 installed successfully" -ForegroundColor Green
            }
            catch {
                Write-host "-> MS Visual C++ 2015-2022 installation failed." -ForegroundColor Red
                Start-Sleep 3
            }
        }
        else {
            Write-host "-> MS Visual C++ 2015-2022 will not be installed." -ForegroundColor Magenta
        }
    }
    else {
        Write-Host "Prerequisites checked. OK" -ForegroundColor Green
    }
}

function Install-WinGet {

    Write-Host "`nChecking if Winget is installed" -ForegroundColor Yellow

    #Check Package Install
    $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" }

    If ([Version]$TestWinGet.Version -ge "2022.728.1939.0") {

        Write-Host "WinGet is Installed" -ForegroundColor Green
    
    }
    Else {

        #Download WinGet MSIXBundle
        Write-Host "-> Not installed. Downloading WinGet..."
        $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v1.3.2091/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($WinGetURL, "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

        #Install WinGet MSIXBundle
        try {
            Write-Host "-> Installing Winget MSIXBundle for App Installer..."
            Add-AppxProvisionedPackage -Online -PackagePath "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense | Out-Null
            Write-Host "Installed Winget MSIXBundle for App Installer" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to intall Winget MSIXBundle for App Installer..." -ForegroundColor Red
        }
    
        #Remove WinGet MSIXBundle
        Remove-Item -Path "$PSScriptRoot\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue

    }

}

function Install-WingetAutoUpdate {

    Write-Host "`nInstalling WAU..." -ForegroundColor Yellow

    try {
        #Copy files to location (and clean old install)
        if (!(Test-Path $WingetUpdatePath)) {
            New-Item -ItemType Directory -Force -Path $WingetUpdatePath | Out-Null
        }
        else {
            if (!$NoClean) {
                Remove-Item -Path "$WingetUpdatePath\*" -Exclude *.log -Recurse -Force
            }
            else {
                #Keep critical files
                Get-ChildItem -Path $WingetUpdatePath -Exclude *.txt,mods,logs | Remove-Item -Recurse -Force
            }
        }
        Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue

        #White List or Black List source not Local if differs
        if ($WingetUpdatePath -ne $ListPath){
            Test-ListPath $ListPath $UseWhiteList
        }
        
        
        #White List or Black List apps
        if ($UseWhiteList) {
            if (!$NoClean) {
                if ((Test-Path "$PSScriptRoot\included_apps.txt")) {
                    Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else {
                    New-Item -Path $WingetUpdatePath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue | Out-Null
                }
            }
            elseif (!(Test-Path "$WingetUpdatePath\included_apps.txt")) {
                if ((Test-Path "$PSScriptRoot\included_apps.txt")) {
                    Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else {
                    New-Item -Path $WingetUpdatePath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        else {
            if (!$NoClean) {
                Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            elseif (!(Test-Path "$WingetUpdatePath\excluded_apps.txt")) {
                Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Set dummy regkeys for notification name and icon
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Application Update" /f | Out-Null
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f | Out-Null

        # Settings for the scheduled task for Updates
        $taskAction = New-ScheduledTaskAction –Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WingetUpdatePath)\winget-upgrade.ps1`""
        $taskTriggers = @()
        if ($UpdatesAtLogon) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
        if ($UpdatesInterval -eq "Daily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At 6AM
        }
        elseif ($UpdatesInterval -eq "Weekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At 6AM -DaysOfWeek 2
        }
        elseif ($UpdatesInterval -eq "BiWeekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At 6AM -DaysOfWeek 2 -WeeksInterval 2
        }
        elseif ($UpdatesInterval -eq "Monthly") {
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

        # Configure Reg Key
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        New-Item $regPath -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayName -Value "Winget-AutoUpdate (WAU)" -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayIcon -Value "C:\Windows\System32\shell32.dll,-16739" -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayVersion -Value $WAUVersion -Force | Out-Null
        New-ItemProperty $regPath -Name InstallLocation -Value $WingetUpdatePath -Force | Out-Null
        New-ItemProperty $regPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WingetUpdatePath\WAU-Uninstall.ps1`"" -Force | Out-Null
        New-ItemProperty $regPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WingetUpdatePath\WAU-Uninstall.ps1`"" -Force | Out-Null
        New-ItemProperty $regPath -Name NoModify -Value 1 -Force | Out-Null
        New-ItemProperty $regPath -Name NoRepair -Value 1 -Force | Out-Null
        New-ItemProperty $regPath -Name VersionMajor -Value ([version]$WAUVersion).Major -Force | Out-Null
        New-ItemProperty $regPath -Name VersionMinor -Value ([version]$WAUVersion).Minor -Force | Out-Null
        New-ItemProperty $regPath -Name Publisher -Value "Romanitho" -Force | Out-Null
        New-ItemProperty $regPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $NotificationLevel -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_PostUpdateActions -Value 0 -PropertyType DWord -Force | Out-Null
        if ($DisableWAUAutoUpdate) {
            New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force | Out-Null
        }
        if ($UseWhiteList) {
            New-ItemProperty $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if (!$RunOnMetered) {
            New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value 1 -PropertyType DWord -Force | Out-Null
        }

        Write-host "WAU Installation succeeded!" -ForegroundColor Green
        Start-sleep 1
        
        #Run Winget ?
        Start-WingetAutoUpdate
    }
    catch {
        Write-host "WAU Installation failed! Run me with admin rights" -ForegroundColor Red
        Start-sleep 1
        return $False
    }
}

function Uninstall-WingetAutoUpdate {
    
    Write-Host "`nUninstalling WAU..." -ForegroundColor Yellow
    
    try {
        #Get registry install location
        $InstallLocation = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\" -Name InstallLocation
        
        #Check if installed location exists and delete
        if (Test-Path ($InstallLocation)) {

            if (!$NoClean) {
                Remove-Item $InstallLocation -Force -Recurse
            }
            else {
                #Keep critical files
                Get-ChildItem -Path $InstallLocation -Exclude *.txt,mods,logs | Remove-Item -Recurse -Force
            }
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
    catch {
        Write-host "Uninstallation failed! Run as admin ?" -ForegroundColor Red
        Start-sleep 1
    }
}

function Start-WingetAutoUpdate {
    #If -DoNotUpdate is true, skip.
    if (!($DoNotUpdate)) {
        #If -Silent, run Winget-AutoUpdate now
        if ($Silent) {
            $RunWinget = 1
        }
        #Ask for WingetAutoUpdate
        else {
            $MsgBoxTitle = "Winget-AutoUpdate"
            $MsgBoxContent = "Would you like to run Winget-AutoUpdate now?"
            $MsgBoxTimeOut = 60
            $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent, $MsgBoxTimeOut, $MsgBoxTitle, 4 + 32)
            if ($MsgBoxReturn -ne 7) {
                $RunWinget = 1
            }
            else {
                $RunWinget = 0
            }
        }
        if ($RunWinget -eq 1) {
            try {
                Write-host "`nRunning Winget-AutoUpdate..." -ForegroundColor Yellow
                Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
                while ((Get-ScheduledTask -TaskName "Winget-AutoUpdate").State -ne 'Ready') {
                    Start-Sleep 1
                }
            }
            catch {
                Write-host "Failed to run Winget-AutoUpdate..." -ForegroundColor Red
            }
        }
    }
    else {
        Write-host "Skip running Winget-AutoUpdate"
    }
}


<# MAIN #>

Write-Host "`n"
Write-Host "`t        888       888        d8888  888     888" -ForegroundColor Magenta
Write-Host "`t        888   o   888       d88888  888     888" -ForegroundColor Magenta
Write-Host "`t        888  d8b  888      d88P888  888     888" -ForegroundColor Magenta
Write-Host "`t        888 d888b 888     d88P 888  888     888" -ForegroundColor Magenta
Write-Host "`t        888d88888b888    d88P  888  888     888" -ForegroundColor Magenta
Write-Host "`t        88888P Y88888   d88P   888  888     888" -ForegroundColor Cyan
Write-Host "`t        8888P   Y8888  d88P    888  888     888" -ForegroundColor Magenta
Write-Host "`t        888P     Y888 d88P     888   Y8888888P`n" -ForegroundColor Magenta
Write-Host "`t                 Winget-AutoUpdate $WAUVersion`n" -ForegroundColor Cyan
Write-Host "`t     https://github.com/Romanitho/Winget-AutoUpdate`n" -ForegroundColor Magenta
Write-Host "`t________________________________________________________`n`n"

if (!$Uninstall) {
    Write-host "Installing WAU to $WingetUpdatePath\"
    Install-Prerequisites
    Install-WinGet
    Install-WingetAutoUpdate
}
else {
    Write-Host "Uninstalling WAU..."
    Uninstall-WingetAutoUpdate
}

Write-host "`nEnd of process." -ForegroundColor Cyan

if (!$Silent) {
    Timeout 10
}
else {
    Start-Sleep 1
}
