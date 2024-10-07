[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $AppListPath,
    [Parameter(Mandatory = $false)] [string] $InstallPath,
    [Parameter(Mandatory = $false)] [string] $CurrentDir,
    [Parameter(Mandatory = $false)] [string] $Upgrade,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall = $false
)

#For troubleshooting
Write-Output "AppListPath:  $AppListPath"
Write-Output "InstallPath:  $InstallPath"
Write-Output "CurrentDir:   $CurrentDir"
Write-Output "Upgrade:      $Upgrade"
Write-Output "Uninstall:    $Uninstall"


<# FUNCTIONS #>

function Add-ACLRule {
    param (
        [System.Security.AccessControl.DirectorySecurity]$acl,
        [string]$sid,
        [string]$access,
        [string]$inheritance = "ContainerInherit,ObjectInherit",
        [string]$propagation = "None",
        [string]$type = "Allow"
    )
    $userSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userSID, $access, $inheritance, $propagation, $type)
    $acl.SetAccessRule($rule)
}

function Install-WingetAutoUpdate {

    Write-Host "### Post install actions ###"

    try {

        # Clean potential old v1 install
        $OldConfRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        $OldWAUConfig = Get-ItemProperty $OldConfRegPath -ErrorAction SilentlyContinue
        if ($OldWAUConfig.InstallLocation) {
            Write-Host "-> Cleanning old v1 WAU version ($($OldWAUConfig.DisplayVersion))"
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""$($OldWAUConfig.InstallLocation)\WAU-Uninstall.ps1""" -Wait
        }

        #Get WAU config
        $WAUconfig = Get-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        Write-Output "-> WAU Config:"
        Write-Output $WAUconfig

        # Settings for the scheduled task for Updates (System)
        Write-Host "-> Installing WAU scheduled tasks"
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($InstallPath)winget-upgrade.ps1`""
        $taskTriggers = @()
        if ($WAUconfig.WAU_UpdatesAtLogon -eq 1) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
        if ($WAUconfig.WAU_UpdatesInterval -eq "Daily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUconfig.WAU_UpdatesAtTime
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "BiDaily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUconfig.WAU_UpdatesAtTime -DaysInterval 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "Weekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "BiWeekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
        }
        elseif ($WAUconfig.WAU_UpdatesInterval -eq "Monthly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUconfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
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
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1" -WorkingDirectory $InstallPath
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        # Set up the task for user apps
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-notify.ps1" -WorkingDirectory $InstallPath
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Settings for the GPO scheduled task
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($InstallPath)WAU-Policies.ps1`""
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

        #Copy App list to install folder (exept on self update)
        if ($AppListPath -and ($AppListPath -notlike "$InstallPath*")) {
            Write-Output "-> Copying $AppListPath to $InstallPath"
            Copy-Item -Path $AppListPath -Destination $InstallPath
        }

        #Copy Mods to install folder
        $ModsFolder = Join-Path $CurrentDir "Mods"
        if (Test-Path $ModsFolder) {
            Write-Output "-> Copying $ModsFolder to $InstallPath"
            Copy-Item -Path $ModsFolder -Destination "$InstallPath" -Recurse
        }

        #Secure folders if not installed to ProgramFiles
        if ($InstallPath -notlike "$env:ProgramFiles*") {

            Write-Output "-> Securing functions and mods folders"
            $directories = @("$InstallPath\functions", "$InstallPath\mods")

            foreach ($directory in $directories) {
                try {
                    #Get dir
                    $dirPath = Get-Item -Path $directory
                    #Get ACL
                    $acl = Get-Acl -Path $dirPath.FullName
                    #Disable inheritance
                    $acl.SetAccessRuleProtection($True, $True)
                    #Remove any existing rules
                    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }

                    # Add new ACL rules
                    Add-ACLRule -acl $acl -sid "S-1-5-18" -access "FullControl"         # SYSTEM Full
                    Add-ACLRule -acl $acl -sid "S-1-5-32-544" -access "FullControl"     # Administrators Full
                    Add-ACLRule -acl $acl -sid "S-1-5-32-545" -access "ReadAndExecute"  # Local Users ReadAndExecute
                    Add-ACLRule -acl $acl -sid "S-1-5-11" -access "ReadAndExecute"      # Authenticated Users ReadAndExecute

                    # Save the updated ACL to the directory
                    Set-Acl -Path $dirPath.FullName -AclObject $acl

                    Write-Host "Permissions for '$directory' have been updated successfully."
                }
                catch {
                    Write-Host "Error setting ACL for '$directory' : $($_.Exception.Message)"
                }
            }

        }

        #Add 1 to Github counter file
        try {
            Invoke-WebRequest -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUconfig.ProductVersion)/WAU_InstallCounter" -UseBasicParsing | Out-Null
            Write-Host "-> Reported installation."
        }
        catch {
            Write-Host "-> Not able to report installation."
        }

        Write-Host "### WAU MSI Post actions succeeded! ###"

    }
    catch {
        Write-Host "### WAU Installation failed! Error $_. ###"
        return $False
    }
}

function Uninstall-WingetAutoUpdate {

    Write-Host "### Uninstalling WAU started! ###"

    Write-Host "-> Removing scheduled tasks."
    Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-Policies" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

    #If upgrade, keep app list and mods. Else, remove.
    if ($Upgrade -like "#{*}") {
        Write-Output "-> Upgrade detected. Keeping *.txt and mods app lists"
    }
    else {
        $AppLists = Get-Item (Join-Path "$InstallPath" "*_apps.txt")
        if ($AppLists) {
            Write-Output "-> Removing items: $AppLists"
            Remove-Item $AppLists -Force
        }
        Remove-Item "$InstallPath\mods" -Recurse -Force
    }

    $ConfFolder = Get-Item (Join-Path "$InstallPath" "config") -ErrorAction SilentlyContinue
    if ($ConfFolder) {
        Write-Output "-> Removing item: $ConfFolder"
        Remove-Item $ConfFolder -Force -Recurse
    }

    Write-Host "### Uninstallation done! ###"
    Start-sleep 1
}


<# MAIN #>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'


# Uninstall
if ($Uninstall) {
    Uninstall-WingetAutoUpdate
}
# Install
else {
    Install-WingetAutoUpdate
}
