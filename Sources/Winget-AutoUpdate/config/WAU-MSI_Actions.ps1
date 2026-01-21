<#
.SYNOPSIS
    MSI installer post-actions script for WAU.

.DESCRIPTION
    Handles installation and uninstallation tasks for the WAU MSI package.
    Creates scheduled tasks and configures permissions.

.PARAMETER AppListPath
    Path to the app list file (excluded_apps.txt or included_apps.txt).

.PARAMETER InstallPath
    WAU installation directory.

.PARAMETER CurrentDir
    Current working directory for the installer.

.PARAMETER Upgrade
    Upgrade product code when performing an upgrade.

.PARAMETER Uninstall
    Switch to trigger uninstallation instead of installation.
#>
[CmdletBinding()]
param(
    [string]$AppListPath,
    [string]$InstallPath,
    [string]$CurrentDir,
    [string]$Upgrade,
    [switch]$Uninstall
)

# Debug output
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
        # Clean old v1 installation if present
        $OldConfRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        $OldWAUConfig = Get-ItemProperty $OldConfRegPath -ErrorAction SilentlyContinue
        if ($OldWAUConfig.InstallLocation) {
            Write-Host "-> Cleaning old v1 WAU version ($($OldWAUConfig.DisplayVersion))"
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""$($OldWAUConfig.InstallLocation)\WAU-Uninstall.ps1""" -Wait
        }

        # Get WAU config from registry
        $WAUconfig = Get-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        Write-Output "-> WAU Config:"
        Write-Output $WAUconfig

        # Create scheduled tasks
        Write-Host "-> Installing WAU scheduled tasks"

        # Main update task (System context)
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"${InstallPath}winget-upgrade.ps1`""

        # Check for saved triggers from upgrade (preserves user customizations)
        $savedTriggersPath = "$env:TEMP\WAU_TaskTriggers.xml"
        if (Test-Path $savedTriggersPath) {
            Write-Output "-> Restoring existing task triggers from upgrade"
            $taskTriggers = Import-Clixml -Path $savedTriggersPath
            Remove-Item $savedTriggersPath -Force -ErrorAction SilentlyContinue
        }
        else {
            # Fresh install: create triggers from registry settings
            $taskTriggers = @()

            if ($WAUconfig.WAU_UpdatesAtLogon -eq 1) {
                $taskTriggers += New-ScheduledTaskTrigger -AtLogOn
            }

            # Interval-based trigger
            $time = $WAUconfig.WAU_UpdatesAtTime
            $delay = $WAUconfig.WAU_UpdatesTimeDelay
            switch ($WAUconfig.WAU_UpdatesInterval) {
                "Daily"    { $taskTriggers += New-ScheduledTaskTrigger -Daily -At $time -RandomDelay $delay }
                "BiDaily"  { $taskTriggers += New-ScheduledTaskTrigger -Daily -At $time -DaysInterval 2 -RandomDelay $delay }
                "Weekly"   { $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $time -DaysOfWeek 2 -RandomDelay $delay }
                "BiWeekly" { $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $time -DaysOfWeek 2 -WeeksInterval 2 -RandomDelay $delay }
                "Monthly"  { $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $time -DaysOfWeek 2 -WeeksInterval 4 -RandomDelay $delay }
            }
        }

        $taskPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

        $taskParams = @{
            Action    = $taskAction
            Principal = $taskPrincipal
            Settings  = $taskSettings
        }
        if ($taskTriggers) { $taskParams.Trigger = $taskTriggers }

        $task = New-ScheduledTask @taskParams
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # User context task
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1" -WorkingDirectory $InstallPath
        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00
        $task = New-ScheduledTask -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Notification task
        $taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File WAU-Notify.ps1" -WorkingDirectory $InstallPath
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        $task = New-ScheduledTask -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # GPO policies task
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"${InstallPath}WAU-Policies.ps1`""
        $taskTrigger = New-ScheduledTaskTrigger -Daily -At 6am
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00
        $task = New-ScheduledTask -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings -Trigger $taskTrigger
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Policies' -TaskPath 'WAU' -InputObject $task -Force | Out-Null

        # Set task permissions for all users
        $scheduler = New-Object -ComObject "Schedule.Service"
        $scheduler.Connect()
        $task = $scheduler.GetFolder("WAU").GetTask("Winget-AutoUpdate")
        $sec = $task.GetSecurityDescriptor(0xF) + '(A;;GRGX;;;AU)'
        $task.SetSecurityDescriptor($sec, 0)

        # Copy app list (except on self-update)
        if ($AppListPath -and ($AppListPath -notlike "$InstallPath*")) {
            Write-Output "-> Copying $AppListPath to $InstallPath"
            Copy-Item -Path $AppListPath -Destination $InstallPath
        }

        # Copy mods folder if present
        $ModsFolder = Join-Path $CurrentDir "Mods"
        if (Test-Path $ModsFolder) {
            Write-Output "-> Copying $ModsFolder to $InstallPath"
            Copy-Item -Path $ModsFolder -Destination $InstallPath -Recurse
        }

        # Secure folders if not in Program Files
        if ($InstallPath -notlike "$env:ProgramFiles*") {
            Write-Output "-> Securing functions and mods folders"

            foreach ($dir in @("$InstallPath\functions", "$InstallPath\mods")) {
                try {
                    $dirPath = Get-Item -Path $dir
                    $acl = Get-Acl -Path $dirPath.FullName
                    $acl.SetAccessRuleProtection($true, $true)
                    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }

                    # Add permissions: SYSTEM, Admins = Full; Users, Authenticated = ReadAndExecute
                    Add-ACLRule -acl $acl -sid "S-1-5-18" -access "FullControl"
                    Add-ACLRule -acl $acl -sid "S-1-5-32-544" -access "FullControl"
                    Add-ACLRule -acl $acl -sid "S-1-5-32-545" -access "ReadAndExecute"
                    Add-ACLRule -acl $acl -sid "S-1-5-11" -access "ReadAndExecute"

                    Set-Acl -Path $dirPath.FullName -AclObject $acl
                    Write-Host "Permissions for '$dir' updated successfully."
                }
                catch {
                    Write-Host "Error setting ACL for '$dir': $($_.Exception.Message)"
                }
            }
        }

        Write-Host "### WAU MSI Post actions succeeded! ###"
    }
    catch {
        Write-Host "### WAU Installation failed! Error: $_. ###"
        return $false
    }
}


function Uninstall-WingetAutoUpdate {
    Write-Host "### Uninstalling WAU started! ###"

    # Keep app lists and mods on upgrade, remove on full uninstall
    if ($Upgrade -like "#{*}") {
        Write-Output "-> Upgrade detected. Keeping *.txt and mods app lists"
        # Save main task triggers to preserve user customizations during upgrade
        $existingTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -TaskPath '\WAU\' -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Output "-> Saving existing task triggers for upgrade"
            $existingTask.Triggers | Export-Clixml -Path "$env:TEMP\WAU_TaskTriggers.xml" -Force
        }
    }
    else {
        $AppLists = Get-Item (Join-Path $InstallPath "*_apps.txt") -ErrorAction SilentlyContinue
        if ($AppLists) {
            Write-Output "-> Removing items: $AppLists"
            Remove-Item $AppLists -Force
        }
        Remove-Item "$InstallPath\mods" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove scheduled tasks
    Write-Host "-> Removing scheduled tasks."
    @("Winget-AutoUpdate", "Winget-AutoUpdate-Notify", "Winget-AutoUpdate-UserContext", "Winget-AutoUpdate-Policies") | ForEach-Object {
        Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    }

    # Remove config folder
    $ConfFolder = Get-Item (Join-Path $InstallPath "config") -ErrorAction SilentlyContinue
    if ($ConfFolder) {
        Write-Output "-> Removing item: $ConfFolder"
        Remove-Item $ConfFolder -Force -Recurse
    }

    Write-Host "### Uninstallation done! ###"
    Start-Sleep 1
}


<# MAIN #>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

if ($Uninstall) {
    Uninstall-WingetAutoUpdate
}
else {
    Install-WingetAutoUpdate
}
