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

.PARAMETER WAUinstallPath
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
    [Parameter(Mandatory = $False)] [Alias('Path', 'WingetUpdatePath')] [String] $WAUinstallPath = "$env:ProgramData\Winget-AutoUpdate",
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

#Include external Functions
. "$PSScriptRoot\Winget-AutoUpdate\functions\Install-Prerequisites.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Invoke-DirProtect.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Update-WinGet.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Update-StoreApps.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Add-Shortcut.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Write-ToLog.ps1"


function Install-WingetAutoUpdate {

    Write-ToLog "Installing WAU..." "Yellow"

    try {
        #Copy files to location
        if (!(Test-Path "$WAUinstallPath\Winget-Upgrade.ps1")) {
            Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-ToLog "-> Running fresh installation..."
        }
        elseif ($NoClean) {
            #Keep critical files
            Get-ChildItem -Path $WAUinstallPath -Exclude *.txt, mods, logs, icons | Remove-Item -Recurse -Force
            Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WAUinstallPath -Exclude icons -Recurse -Force -ErrorAction SilentlyContinue #Exclude icons if personalized
            Write-ToLog "-> Updating previous installation. Keeping critical existing files..."
        }
        else {
            #Keep logs only
            Get-ChildItem -Path $WAUinstallPath -Exclude logs | Remove-Item -Recurse -Force
            Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-ToLog "-> Updating previous installation..."
        }

        #White List or Black List apps
        if ($UseWhiteList) {
            #If fresh install and "included_apps.txt" exists, copy the list to WAU
            if ((!$NoClean) -and (Test-Path "$PSScriptRoot\included_apps.txt")) {
                Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "-> Copied a brand new Whitelist."
            }
            #Else, only copy the "included_apps.txt" list if not existing in WAU
            elseif (!(Test-Path "$WAUinstallPath\included_apps.txt")) {
                Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "-> No Whitelist was existing. Copied from install sources."
            }
        }
        else {
            if (!$NoClean) {
                Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "-> Copied brand new Blacklist."
            }
            elseif (!(Test-Path "$WAUinstallPath\excluded_apps.txt")) {
                Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WAUinstallPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "-> No Blacklist was existing. Copied from install sources."
            }
        }

        # Set dummy regkeys for notification name and icon
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Application Update" /f | Out-Null
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f | Out-Null

        # Clean potential old install
        Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
        Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
        Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

        # Settings for the scheduled task for Updates (System)
        Write-ToLog "-> Installing WAU scheduled tasks"
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WAUinstallPath)\winget-upgrade.ps1`""
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
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task in User context
        $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\winget-upgrade.ps1`"`""
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        # Set up the task for user apps
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\winget-notify.ps1`"`""
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the GPO scheduled task
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WAUinstallPath)\WAU-Policies.ps1`""
        $tasktrigger = New-ScheduledTaskTrigger -Daily -At 6am
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Policies' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        #Set task readable/runnable for all users
        $scheduler = New-Object -ComObject "Schedule.Service"
        $scheduler.Connect()
        $task = $scheduler.GetFolder("WAU").GetTask("Winget-AutoUpdate")
        $sec = $task.GetSecurityDescriptor(0xF)
        $sec = $sec + '(A;;GRGX;;;AU)'
        $task.SetSecurityDescriptor($sec, 0)

        # Configure Reg Key
        Write-ToLog "-> Setting Registry config"
        New-Item $regPath -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayName -Value "Winget-AutoUpdate (WAU)" -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayIcon -Value "C:\Windows\System32\shell32.dll,-16739" -Force | Out-Null
        New-ItemProperty $regPath -Name DisplayVersion -Value $WAUVersion -Force | Out-Null
        New-ItemProperty $regPath -Name InstallLocation -Value $WAUinstallPath -Force | Out-Null
        New-ItemProperty $regPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WAUinstallPath\WAU-Uninstall.ps1`"" -Force | Out-Null
        New-ItemProperty $regPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WAUinstallPath\WAU-Uninstall.ps1`"" -Force | Out-Null
        New-ItemProperty $regPath -Name NoModify -Value 1 -Force | Out-Null
        New-ItemProperty $regPath -Name NoRepair -Value 1 -Force | Out-Null
        New-ItemProperty $regPath -Name Publisher -Value "Romanitho" -Force | Out-Null
        New-ItemProperty $regPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $NotificationLevel -Force | Out-Null
        if ($WAUVersion -match "-") {
            New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force | Out-Null
        }
        else {
            New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force | Out-Null
        }
        New-ItemProperty $regPath -Name WAU_PostUpdateActions -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_MaxLogFiles -Value $MaxLogFiles -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_MaxLogSize -Value $MaxLogSize -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_UpdatesAtTime -Value $UpdatesAtTime -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_UpdatesInterval -Value $UpdatesInterval -Force | Out-Null
        if ($UpdatesAtLogon) {
            New-ItemProperty $regPath -Name WAU_UpdatesAtLogon -Value 1 -PropertyType DWord -Force | Out-Null
        }
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
        if ($InstallUserContext) {
            New-ItemProperty $regPath -Name WAU_UserContext -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if ($DesktopShortcut) {
            New-ItemProperty $regPath -Name WAU_DesktopShortcut -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if ($StartMenuShortcut) {
            New-ItemProperty $regPath -Name WAU_StartMenuShortcut -Value 1 -PropertyType DWord -Force | Out-Null
        }

        #Security check
        Write-ToLog "-> Checking Mods Directory:"
        $Protected = Invoke-DirProtect "$WAUinstallPath\mods"
        if ($Protected -eq $True) {
            Write-ToLog "   The mods directory is secured!" "Cyan"
        }
        else {
            Write-ToLog "   Error: The mods directory couldn't be verified as secured!" "Red"
        }
        Write-ToLog "-> Checking Functions Directory:"
        $Protected = Invoke-DirProtect "$WAUinstallPath\Functions"
        if ($Protected -eq $True) {
            Write-ToLog "   The Functions directory is secured!" "Cyan"
        }
        else {
            Write-ToLog "   Error: The Functions directory couldn't be verified as secured!" "Red"
        }

        #Create Shortcuts
        if ($StartMenuShortcut) {
            if (!(Test-Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) {
                New-Item -ItemType Directory -Force -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" | Out-Null
            }
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Check for updated Apps.lnk" "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Open logs.lnk" "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\user-run.ps1`" -Logs`"" "${env:SystemRoot}\System32\shell32.dll,-16763" "Open existing WAU logs..."
            Add-Shortcut "wscript.exe" "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Web Help.lnk" "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\user-run.ps1`" -Help`"" "${env:SystemRoot}\System32\shell32.dll,-24" "Help for WAU..."
        }

        if ($DesktopShortcut) {
            Add-Shortcut "wscript.exe" "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" "`"$($WAUinstallPath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WAUinstallPath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" "Manual start of Winget-AutoUpdate (WAU)..."
        }

        #Add 1 to counter file
        try {
            Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUVersion)/WAU_InstallCounter" | Out-Null
        }
        catch {
            Write-ToLog "-> Not able to report installation." "Yellow"
        }

        Write-ToLog "-> WAU Installation succeeded!`n" "Green"
        Start-sleep 1

        #Run Winget ?
        Start-WingetAutoUpdate
    }
    catch {
        Write-ToLog "-> WAU Installation failed! Error $_ - Try running me with admin rights.`n" "Red"
        Start-sleep 1
        return $False
    }
}

function Uninstall-WingetAutoUpdate {

    Write-ToLog "Uninstalling WAU started!" "Yellow"

    #Get registry install location
    $InstallLocation = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\" -Name InstallLocation -ErrorAction SilentlyContinue

    #Check if installed location exists and delete
    if ($InstallLocation) {

        try {
            if (!$NoClean) {
                Write-ToLog "-> Removing files and config."
                Get-ChildItem -Path $InstallLocation -Exclude logs | Remove-Item -Force -Recurse
                if (Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log") {
                    Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -Force -ErrorAction SilentlyContinue | Out-Null
                }
                if (Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log") {
                    Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            else {
                #Keep critical files
                Write-ToLog "-> Removing files. Keeping config."
                Get-ChildItem -Path $InstallLocation -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force
            }
            & reg delete "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /f | Out-Null
            & reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" /f | Out-Null

            if ((Test-Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) {
                Remove-Item -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" -Recurse -Force | Out-Null
            }

            if ((Test-Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk")) {
                Remove-Item -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" -Force | Out-Null
            }

            Write-ToLog "-> Removing scheduled tasks."
            Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
            Get-ScheduledTask -TaskName "Winget-AutoUpdate-Policies" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

            Write-ToLog "Uninstallation succeeded!`n" "Green"
            Start-sleep 1
        }
        catch {
            Write-ToLog "Uninstallation failed! Run as admin ?`n" "Red"
            Start-sleep 1
        }
    }
    else {
        Write-ToLog "WAU is not installed!`n" "Red"
        Start-sleep 1
    }
}

function Start-WingetAutoUpdate {
    #If -DoNotUpdate is true, skip.
    if (!($DoNotUpdate)) {
        #If -Silent, run Winget-AutoUpdate now
        if ($Silent) {
            $RunWinget = $True
        }
        #Ask for WingetAutoUpdate
        else {
            $MsgBoxTitle = "Winget-AutoUpdate"
            $MsgBoxContent = "Would you like to run Winget-AutoUpdate now?"
            $MsgBoxTimeOut = 60
            $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent, $MsgBoxTimeOut, $MsgBoxTitle, 4 + 32)
            if ($MsgBoxReturn -ne 7) {
                $RunWinget = $True
            }
        }
        if ($RunWinget) {
            try {
                Write-ToLog "Running Winget-AutoUpdate..." "Yellow"
                Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
                while ((Get-ScheduledTask -TaskName "Winget-AutoUpdate").State -ne 'Ready') {
                    Start-Sleep 1
                }
            }
            catch {
                Write-ToLog "Failed to run Winget-AutoUpdate..." "Red"
            }
        }
    }
    else {
        Write-ToLog "Skip running Winget-AutoUpdate"
    }
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

#Config console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Workaround for ARM64 (Access Denied / Win32 internal Server error)
$Script:ProgressPreference = 'SilentlyContinue'

#Set install log file
$Script:LogFile = "$WAUinstallPath\logs\WAU-Installer.log"

Write-Host "`n "
Write-Host "`t        888       888        d8888  888     888" -ForegroundColor Magenta
Write-Host "`t        888   o   888       d88888  888     888" -ForegroundColor Magenta
Write-Host "`t        888  d8b  888      d88P888  888     888" -ForegroundColor Magenta
Write-Host "`t        888 d888b 888     d88P 888  888     888" -ForegroundColor Magenta
Write-Host "`t        888d88888b888    d88P  888  888     888" -ForegroundColor Magenta
Write-Host "`t        88888P Y88888   d88P   888  888     888" -ForegroundColor Cyan
Write-Host "`t        8888P   Y8888  d88P    888  888     888" -ForegroundColor Magenta
Write-Host "`t        888P     Y888 d88P     888   Y8888888P`n" -ForegroundColor Magenta
Write-Host "`t                Winget-AutoUpdate $WAUVersion`n" -ForegroundColor Cyan
Write-Host "`t     https://github.com/Romanitho/Winget-AutoUpdate`n" -ForegroundColor Magenta
Write-Host "`t________________________________________________________`n"

#Define WAU registry key
$Script:regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

if (!$Uninstall) {
    Write-ToLog "  INSTALLING WAU" -LogColor "Cyan" -IsHeader
    Install-Prerequisites
    $UpdateWinget = Update-Winget
    if ($UpdateWinget -ne "fail") {
        Install-WingetAutoUpdate
    }
    else {
        Write-ToLog "Winget is mandatory to execute WAU." "Red"
    }
}
else {
    Write-ToLog " UNINSTALLING WAU" -LogColor "Cyan" -IsHeader
    Uninstall-WingetAutoUpdate
}

if (Test-Path "$WAUinstallPath\Version.txt") {
    Remove-Item "$WAUinstallPath\Version.txt" -Force
}

Write-ToLog "End of process." "Cyan"
Start-Sleep 3
