<#
.SYNOPSIS
Handle GPO/Polices

.DESCRIPTION
Daily update settings from policies
#>

#Import functions
. "$PSScriptRoot\functions\Get-WAUConfig.ps1"

#Check if GPO Management is enabled
$ActivateGPOManagement = Get-ItemPropertyValue "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_ActivateGPOManagement" -ErrorAction SilentlyContinue
if ($ActivateGPOManagement -eq 1) {
    #Add (or update) tag to activate WAU-Policies Management
    New-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name WAU_RunGPOManagement -Value 1 -Force | Out-Null
}

#Get WAU settings
$WAUConfig = Get-WAUConfig

#Check if GPO got applied from Get-WAUConfig (tag)
if ($WAUConfig.WAU_RunGPOManagement -eq 1) {

    #Log init
    $GPOLogDirectory = Join-Path -Path $WAUConfig.InstallLocation -ChildPath "logs"
    if (!(Test-Path -Path $GPOLogDirectory)) {
        New-Item -ItemType Directory -Path $GPOLogDirectory -Force | Out-Null
    }
    $GPOLogFile = Join-Path -Path $GPOLogDirectory -ChildPath "LatestAppliedSettings.txt"
    Set-Content -Path $GPOLogFile -Value "###  POLICY CYCLE - $(Get-Date)  ###`n"

    #Reset WAU_RunGPOManagement if not GPO managed anymore (This is used to run this job one last time and reset initial settings)
    if ($($WAUConfig.WAU_ActivateGPOManagement -eq 1)) {
        Add-Content -Path $GPOLogFile -Value "GPO Management Enabled. Policies updated."
    }
    else {
        New-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name WAU_RunGPOManagement -Value 0 -Force | Out-Null
        $WAUConfig.WAU_RunGPOManagement = 0
        Add-Content -Path $GPOLogFile -Value "GPO Management Disabled. Policies removed."
    }

    #Get Winget-AutoUpdate scheduled task
    $WAUTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue

    #Update 'Winget-AutoUpdate' scheduled task settings
    $currentTriggers = $WAUTask.Triggers
    $configChanged = $false

    #Check if LogOn trigger setting has changed
    $hasLogonTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" }
    if (($WAUConfig.WAU_UpdatesAtLogon -eq 1 -and -not $hasLogonTrigger) -or 
        ($WAUConfig.WAU_UpdatesAtLogon -ne 1 -and $hasLogonTrigger)) {
        $configChanged = $true
    }

    #Check if schedule type has changed
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

    #Check if delay is set
    if ($WAUConfig.WAU_UpdatesTimeDelay) {
        $randomDelay = [TimeSpan]::ParseExact($WAUConfig.WAU_UpdatesTimeDelay, "hh\:mm", $null)
    } else {   
        $randomDelay = [TimeSpan]::ParseExact("00:00", "hh\:mm", $null) #setting to 00:00 disables the random delay
    }

    #Check if delay has changed
    $timeTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -ne "MSFT_TaskLogonTrigger" } | Select-Object -First 1
    if ($timeTrigger.RandomDelay -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
        $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $existingRandomDelay = New-TimeSpan -Hours $hours -Minutes $minutes
    }
    if ($existingRandomDelay -ne $randomDelay) {
        $configChanged = $true
    }
    #Check if schedule time has changed
    if ($currentIntervalType -ne "None" -and $currentIntervalType -ne "Never") {
        if ($timeTrigger) {
            $currentTime = [DateTime]::Parse($timeTrigger.StartBoundary).ToString("HH:mm:ss")
            if ($currentTime -ne $WAUConfig.WAU_UpdatesAtTime) {
                $configChanged = $true
            }
        }
    }

    #Only update triggers if configuration has changed
    if ($configChanged) {
        $taskTriggers = @()
        if ($WAUConfig.WAU_UpdatesAtLogon -eq 1) {
            $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
        }
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
        
        #If trigger(s) set
        if ($taskTriggers) {
            #Edit scheduled task
            Set-ScheduledTask -TaskPath $WAUTask.TaskPath -TaskName $WAUTask.TaskName -Trigger $taskTriggers | Out-Null
        }
        #If not, remove trigger(s)
        else {
            #Remove by setting past due date
            $tasktriggers = New-ScheduledTaskTrigger -Once -At "01/01/1970"
            Set-ScheduledTask -TaskPath $WAUTask.TaskPath -TaskName $WAUTask.TaskName -Trigger $tasktriggers | Out-Null
        }
    }
    
    #Log latest applied config
    Add-Content -Path $GPOLogFile -Value "`nLatest applied settings:"
    $WAUConfig.PSObject.Properties | Where-Object { $_.Name -like "WAU_*" } | Select-Object Name, Value | Out-File -Encoding default -FilePath $GPOLogFile -Append
}

Exit 0
