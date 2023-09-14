<#
.SYNOPSIS
Configure Winget to daily update installed apps.

.DESCRIPTION
Install powershell scripts and scheduled task to daily run Winget upgrade and notify connected users.
Posibility to exclude apps from auto-update
https://github.com/Romanitho/Winget-AutoUpdate

.PARAMETER Silent
Install Winget-AutoUpdate and prerequisites silently

.PARAMETER MaxLogFiles
Specify number of allowed log files (Default is 3 of 0-99: Setting MaxLogFiles to 0 don't delete any old archived log files, 1 keeps the original one and just let it grow)

.PARAMETER MaxLogSize
Specify the size of the log file in bytes before rotating. (Default is 1048576 = 1 MB)

.PARAMETER WingetUpdatePath
Specify Winget-AutoUpdate installation localtion. Default: C:\ProgramData\Winget-AutoUpdate\

.PARAMETER DoNotUpdate
Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation.

.PARAMETER DisableWAUAutoUpdate
Disable Winget-AutoUpdate update checking. By default, WAU auto update if new version is available on Github.

.PARAMETER UseWhiteList
Use White List instead of Black List. This setting will not create the "exclude_apps.txt" but "include_apps.txt"

.PARAMETER ListPath
Get Black/White List from Path (URL/UNC/GPO/Local)

.PARAMETER ModsPath
Get mods from Path (URL/UNC/Local/AzureBlob)

.PARAMETER AzureBlobURL
Set the Azure Storage Blob URL including the SAS token. The token requires at a minimum 'Read' and 'List' permissions. It is recommended to set this at the container level

.PARAMETER Uninstall
Remove scheduled tasks and scripts.

.PARAMETER NoClean
Keep critical files when installing/uninstalling

.PARAMETER DesktopShortcut
Create a shortcut for user interaction on the Desktop to run task "Winget-AutoUpdate"

.PARAMETER StartMenuShortcut
Create shortcuts for user interaction in the Start Menu to run task "Winget-AutoUpdate", open Logs and Web Help

.PARAMETER NotificationLevel
Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

.PARAMETER UpdatesAtLogon
Set WAU to run at user logon.

.PARAMETER UpdatesInterval
Specify the update frequency: Daily (Default), BiDaily, Weekly, BiWeekly, Monthly or Never

.PARAMETER UpdatesAtTime
Specify the time of the update interval execution time. Default 6AM

.PARAMETER RunOnMetered
Run WAU on metered connection. Default No.

.PARAMETER InstallUserContext
Install WAU with system and user context executions

.PARAMETER BypassListForUsers
Configure WAU to bypass the Black/White list when run in user context. Applications installed in system context will be ignored under user context.

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -DoNotUpdate -MaxLogFiles 4 -MaxLogSize 2097152

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -UseWhiteList

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -ListPath https://www.domain.com/WAULists -StartMenuShortcut -UpdatesInterval BiDaily

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -ModsPath https://www.domain.com/WAUMods -DesktopShortcut -UpdatesInterval Weekly

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -UpdatesAtLogon -UpdatesInterval Weekly

.EXAMPLE
.\Winget-AutoUpdate-Install.ps1 -Silent -Uninstall -NoClean

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $False)] [Alias('S')] [Switch] $Silent = $false,
    [Parameter(Mandatory = $False)] [Alias('Path')] [String] $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate",
    [Parameter(Mandatory = $False)] [Alias('List')] [String] $ListPath,
    [Parameter(Mandatory = $False)] [Alias('Mods')] [String] $ModsPath,
    [Parameter(Mandatory = $False)] [Alias('AzureBlobURL')] [String] $AzureBlobSASURL,
    [Parameter(Mandatory = $False)] [Switch] $DoNotUpdate = $false,
    [Parameter(Mandatory = $False)] [Switch] $DisableWAUAutoUpdate = $false,
    [Parameter(Mandatory = $False)] [Switch] $RunOnMetered = $false,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall = $false,
    [Parameter(Mandatory = $False)] [Switch] $NoClean = $false,
    [Parameter(Mandatory = $False)] [Switch] $DesktopShortcut = $false,
    [Parameter(Mandatory = $False)] [Switch] $StartMenuShortcut = $false,
    [Parameter(Mandatory = $False)] [Switch] $UseWhiteList = $false,
    [Parameter(Mandatory = $False)] [ValidateSet("Full", "SuccessOnly", "None")] [String] $NotificationLevel = "Full",
    [Parameter(Mandatory = $False)] [Switch] $UpdatesAtLogon = $false,
    [Parameter(Mandatory = $False)] [ValidateSet("Daily", "BiDaily", "Weekly", "BiWeekly", "Monthly", "Never")] [String] $UpdatesInterval = "Daily",
    [Parameter(Mandatory = $False)] [DateTime] $UpdatesAtTime = ("06am"),
    [Parameter(Mandatory = $False)] [Switch] $BypassListForUsers = $false,
    [Parameter(Mandatory = $False)] [Switch] $InstallUserContext = $false,
    [Parameter(Mandatory = $False)] [ValidateRange(0, 99)] [int32] $MaxLogFiles = 3,
    [Parameter(Mandatory = $False)] [int64] $MaxLogSize = 1048576 # in bytes, default is 1048576 = 1 MB
)


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
                Invoke-WebRequest $SourceURL -UseBasicParsing -OutFile (New-Item -Path $Installer -Force)
                Write-host "-> Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
                Remove-Item $Installer -ErrorAction Ignore
                Write-host "MS Visual C++ 2015-2022 installed successfully" -ForegroundColor Green
            }
            catch {
                Write-host "MS Visual C++ 2015-2022 installation failed." -ForegroundColor Red
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

    #Current: v1.5.2201 = 1.20.2201.0 = 2023.808.2243.0
    If ([Version]$TestWinGet.Version -ge "2023.808.2243.0") {

        Write-Host "Winget is Installed" -ForegroundColor Green

    }
    Else {

        Write-Host "-> Winget is not installed:"

        #Check if $WingetUpdatePath exist
        if (!(Test-Path $WingetUpdatePath)) {
            New-Item -ItemType Directory -Force -Path $WingetUpdatePath | Out-Null
        }

        #Downloading and Installing Dependencies in SYSTEM context
        if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.7')) {
            Write-Host "-> Downloading Microsoft.UI.Xaml.2.7..."
            $UiXamlUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.0"
            $UiXamlZip = "$WingetUpdatePath\Microsoft.UI.XAML.2.7.zip"
            Invoke-RestMethod -Uri $UiXamlUrl -OutFile $UiXamlZip
            Expand-Archive -Path $UiXamlZip -DestinationPath "$WingetUpdatePath\extracted" -Force
            try {
                Write-Host "-> Installing Microsoft.UI.Xaml.2.7..."
                Add-AppxProvisionedPackage -Online -PackagePath "$WingetUpdatePath\extracted\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx" -SkipLicense | Out-Null
                Write-host "Microsoft.UI.Xaml.2.7 installed successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to intall Wicrosoft.UI.Xaml.2.7..." -ForegroundColor Red
            }
            Remove-Item -Path $UiXamlZip -Force
            Remove-Item -Path "$WingetUpdatePath\extracted" -Force -Recurse
        }

        if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop')) {
            Write-Host "-> Downloading Microsoft.VCLibs.140.00.UWPDesktop..."
            $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            $VCLibsFile = "$WingetUpdatePath\Microsoft.VCLibs.x64.14.00.Desktop.appx"
            Invoke-RestMethod -Uri $VCLibsUrl -OutFile $VCLibsFile
            try {
                Write-Host "-> Installing Microsoft.VCLibs.140.00.UWPDesktop..."
                Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense | Out-Null
                Write-host "Microsoft.VCLibs.140.00.UWPDesktop installed successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to intall Microsoft.VCLibs.140.00.UWPDesktop..." -ForegroundColor Red
            }
            Remove-Item -Path $VCLibsFile -Force
        }

        #Download WinGet MSIXBundle
        Write-Host "-> Downloading Winget MSIXBundle for App Installer..."
        $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v1.5.2201/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($WinGetURL, "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

        #Install WinGet MSIXBundle in SYSTEM context
        try {
            Write-Host "-> Installing Winget MSIXBundle for App Installer..."
            Add-AppxProvisionedPackage -Online -PackagePath "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense | Out-Null
            Write-host "Winget MSIXBundle for App Installer installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to intall Winget MSIXBundle for App Installer..." -ForegroundColor Red
        }

        #Remove WinGet MSIXBundle
        Remove-Item -Path "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue

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
                Get-ChildItem -Path $WingetUpdatePath -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force
            }
        }
        Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue

        #White List or Black List apps
        if ($UseWhiteList) {
            if (!$NoClean) {
                if ((Test-Path "$PSScriptRoot\included_apps.txt")) {
                    Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else {
                    if (!$ListPath) {
                        New-Item -Path $WingetUpdatePath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
            elseif (!(Test-Path "$WingetUpdatePath\included_apps.txt")) {
                if ((Test-Path "$PSScriptRoot\included_apps.txt")) {
                    Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else {
                    if (!$ListPath) {
                        New-Item -Path $WingetUpdatePath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue | Out-Null
                    }
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
        $taskAction = New-ScheduledTaskAction -Execute "$WingetUpdatePath\ServiceUI.exe" -Argument "-process:explorer.exe %windir%\System32\wscript.exe \`"$WingetUpdatePath\Invisible.vbs \`" \`"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \`"\`"$WingetUpdatePath\winget-upgrade.ps1\`"\`"\`""
        $taskTriggers = @()
        if ($UpdatesAtLogon) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
        if ($UpdatesInterval -eq "Daily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime
        }
        elseif ($UpdatesInterval -eq "BiDaily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime -DaysInterval 2
        }
        elseif ($UpdatesInterval -eq "Weekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2
        }
        elseif ($UpdatesInterval -eq "BiWeekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
        }
        elseif ($UpdatesInterval -eq "Monthly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
        }
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

        # Set up the task, and register it
        if ($taskTriggers) {
            $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTriggers
        }
        else {
            $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        }
        
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -InputObject $task -Force | Out-Null

        if ($InstallUserContext) {
            # Settings for the scheduled task in User context
            $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-upgrade.ps1`"`""
            $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
            $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

            # Set up the task for user apps
            $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
            Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -InputObject $task -Force | Out-Null
        }

        #Set task readable/runnable for all users
        $scheduler = New-Object -ComObject "Schedule.Service"
        $scheduler.Connect()
        $task = $scheduler.GetFolder("").GetTask("Winget-AutoUpdate")
        $sec = $task.GetSecurityDescriptor(0xF)
        $sec = $sec + '(A;;GRGX;;;AU)'
        $task.SetSecurityDescriptor($sec, 0)

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
        New-ItemProperty $regPath -Name Publisher -Value "Romanitho" -Force | Out-Null
        New-ItemProperty $regPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $NotificationLevel -Force | Out-Null
        if ($WAUVersion -match "-"){
            New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force | Out-Null
        }
        else {
            New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force | Out-Null
        }
        New-ItemProperty $regPath -Name WAU_PostUpdateActions -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_MaxLogFiles -Value $MaxLogFiles -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_MaxLogSize -Value $MaxLogSize -PropertyType DWord -Force | Out-Null
        if ($DisableWAUAutoUpdate) {
            New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force | Out-Null
        }
        if ($UseWhiteList) {
            New-ItemProperty $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if (!$RunOnMetered) {
            New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if ($ListPath) {
            New-ItemProperty $regPath -Name WAU_ListPath -Value $ListPath -Force | Out-Null
        }
        if ($ModsPath) {
            New-ItemProperty $regPath -Name WAU_ModsPath -Value $ModsPath -Force | Out-Null
        }
        if ($AzureBlobSASURL) {
            New-ItemProperty $regPath -Name WAU_AzureBlobSASURL -Value $AzureBlobSASURL -Force | Out-Null
        }
        if ($BypassListForUsers) {
            New-ItemProperty $regPath -Name WAU_BypassListForUsers -Value 1 -PropertyType DWord -Force | Out-Null
        }

        #Log file and symlink initialization
        . "$WingetUpdatePath\functions\Start-Init.ps1"
        Start-Init

        #Security check
        Write-host "`nChecking Mods Directory:" -ForegroundColor Yellow
        . "$WingetUpdatePath\functions\Invoke-ModsProtect.ps1"
        $Protected = Invoke-ModsProtect "$WingetUpdatePath\mods"
        if ($Protected -eq $True) {
            Write-Host "The mods directory is now secured!`n" -ForegroundColor Green
        }
        elseif ($Protected -eq $False) {
            Write-Host "The mods directory was already secured!`n" -ForegroundColor Green
        }
        else {
            Write-Host "Error: The mods directory couldn't be verified as secured!`n" -ForegroundColor Red
        }

        #Create Shortcuts
        if ($StartMenuShortcut) {
            if (!(Test-Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) {
                New-Item -ItemType Directory -Force -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" | Out-Null
            }
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Check for updated Apps.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Open logs.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`" -Logs`"" "${env:SystemRoot}\System32\shell32.dll,-16763" "Open existing WAU logs..."
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Web Help.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`" -Help`"" "${env:SystemRoot}\System32\shell32.dll,-24" "Help for WAU..."
        }

        if ($DesktopShortcut) {
            Add-Shortcut "wscript.exe" "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
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
                if (Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log") {
                    Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -Force -ErrorAction SilentlyContinue | Out-Null
                }
                if (Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log") {
                    Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            else {
                #Keep critical files
                Get-ChildItem -Path $InstallLocation -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force
            }
            Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            & reg delete "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /f | Out-Null
            & reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" /f | Out-Null

            if ((Test-Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) {
                Remove-Item -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" -Recurse -Force | Out-Null
            }

            if ((Test-Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk")) {
                Remove-Item -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" -Force | Out-Null
            }

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

function Add-Shortcut ($Target, $Shortcut, $Arguments, $Icon, $Description) {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($Shortcut)
    $Shortcut.TargetPath = $Target
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = $Icon
    $Shortcut.Description = $Description
    $Shortcut.Save()
}


<# APP INFO #>

$WAUVersion = Get-Content "$PSScriptRoot\Winget-AutoUpdate\Version.txt" -ErrorAction SilentlyContinue


<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -NoNewWindow -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}

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

Remove-Item "$WingetUpdatePath\Version.txt" -Force
Write-host "`nEnd of process." -ForegroundColor Cyan
Start-Sleep 3
