<#
.SYNOPSIS
    Applies Group Policy settings to WAU scheduled tasks.

.DESCRIPTION
    Reads WAU configuration from GPO registry keys and updates the
    Winget-AutoUpdate scheduled task triggers accordingly.
    Handles daily, bi-daily, weekly, bi-weekly, and monthly schedules,
    as well as logon triggers and time delays.

.NOTES
    This script is executed by the WAU-Policies scheduled task.
    GPO registry path: HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate
    Logs applied settings to: logs\LatestAppliedSettings.txt
#>

# Import configuration function
. "$PSScriptRoot\functions\Get-WAUConfig.ps1"

# Check if GPO management is enabled
$GPOManagementDetected = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

if ($GPOManagementDetected) {

    # Load WAU configuration (with GPO overrides)
    $WAUConfig = Get-WAUConfig

    # Initialize logging
    $GPOLogDirectory = Join-Path -Path $WAUConfig.InstallLocation -ChildPath "logs"
    if (!(Test-Path -Path $GPOLogDirectory)) {
        New-Item -ItemType Directory -Path $GPOLogDirectory -Force | Out-Null
    }
    $GPOLogFile = Join-Path -Path $GPOLogDirectory -ChildPath "LatestAppliedSettings.txt"
    Set-Content -Path $GPOLogFile -Value "###  POLICY CYCLE - $(Get-Date)  ###`n"

    # Get current scheduled task configuration
    $WAUTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
    $currentTriggers = $WAUTask.Triggers
    $configChanged = $false

    # === Check if LogOn trigger setting has changed ===
    $hasLogonTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" }
    if (($WAUConfig.WAU_UpdatesAtLogon -eq 1 -and -not $hasLogonTrigger) -or
        ($WAUConfig.WAU_UpdatesAtLogon -ne 1 -and $hasLogonTrigger)) {
        $configChanged = $true
    }

    # === Detect current schedule type ===
    $currentIntervalType = "None"
    foreach ($trigger in $currentTriggers) {
        if ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 1) {
            $currentIntervalType = "Daily"
            break
        }
        elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 2) {
            $currentIntervalType = "BiDaily"
            break
        }
        elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 1) {
            $currentIntervalType = "Weekly"
            break
        }
        elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 2) {
            $currentIntervalType = "BiWeekly"
            break
        }
        elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 4) {
            $currentIntervalType = "Monthly"
            break
        }
        elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskTimeTrigger" -and [DateTime]::Parse($trigger.StartBoundary) -lt (Get-Date)) {
            $currentIntervalType = "Never"
            break
        }
    }

    if ($currentIntervalType -ne $WAUConfig.WAU_UpdatesInterval) {
        $configChanged = $true
    }

    # === Check if delay has changed ===
    $randomDelay = [TimeSpan]::ParseExact($WAUConfig.WAU_UpdatesTimeDelay, "hh\:mm", $null)
    $timeTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -ne "MSFT_TaskLogonTrigger" } | Select-Object -First 1
    if ($timeTrigger.RandomDelay -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
        $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $existingRandomDelay = New-TimeSpan -Hours $hours -Minutes $minutes
    }
    if ($existingRandomDelay -ne $randomDelay) {
        $configChanged = $true
    }

    # === Check if schedule time has changed ===
    if ($currentIntervalType -ne "None" -and $currentIntervalType -ne "Never") {
        if ($timeTrigger) {
            $currentTime = [DateTime]::Parse($timeTrigger.StartBoundary).ToString("HH:mm:ss")
            if ($currentTime -ne $WAUConfig.WAU_UpdatesAtTime) {
                $configChanged = $true
            }
        }
    }

    # === Update triggers if configuration changed ===
    if ($configChanged) {
        $taskTriggers = @()

        # Add logon trigger if enabled
        if ($WAUConfig.WAU_UpdatesAtLogon -eq 1) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }

        # Add time-based trigger based on interval type
        if ($WAUConfig.WAU_UpdatesInterval -eq "Daily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUConfig.WAU_UpdatesAtTime -RandomDelay $randomDelay
        }
        elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiDaily") {
            $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUConfig.WAU_UpdatesAtTime -DaysInterval 2 -RandomDelay $randomDelay
        }
        elseif ($WAUConfig.WAU_UpdatesInterval -eq "Weekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2 -RandomDelay $randomDelay
        }
        elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiWeekly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2 -RandomDelay $randomDelay
        }
        elseif ($WAUConfig.WAU_UpdatesInterval -eq "Monthly") {
            $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4 -RandomDelay $randomDelay
        }

        # Apply new triggers or disable task
        if ($taskTriggers) {
            Set-ScheduledTask -TaskPath $WAUTask.TaskPath -TaskName $WAUTask.TaskName -Trigger $taskTriggers | Out-Null
        }
        else {
            # Disable by setting a past due date
            $tasktriggers = New-ScheduledTaskTrigger -Once -At "01/01/1970"
            Set-ScheduledTask -TaskPath $WAUTask.TaskPath -TaskName $WAUTask.TaskName -Trigger $tasktriggers | Out-Null
        }
    }

    # Log applied configuration
    Add-Content -Path $GPOLogFile -Value "`nLatest applied settings:"
    $WAUConfig.PSObject.Properties | Where-Object { $_.Name -like "WAU_*" } | Select-Object Name, Value | Out-File -Encoding default -FilePath $GPOLogFile -Append

}

Exit 0
