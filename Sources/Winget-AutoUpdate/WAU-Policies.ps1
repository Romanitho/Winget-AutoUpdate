<#
.SYNOPSIS
Handle GPO/Polices

.DESCRIPTION
Daily update settings from policies
#>

#Import functions
. "$PSScriptRoot\functions\Get-WAUConfig.ps1"
. "$PSScriptRoot\functions\Add-Shortcut.ps1"

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
    $GPOLogFile = "$($WAUConfig.InstallLocation)\logs\LatestAppliedSettings.txt"
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
    $taskTriggers = @()
    if ($WAUConfig.WAU_UpdatesAtLogon -eq 1) {
        $tasktriggers += New-ScheduledTaskTrigger -AtLogOn
    }
    if ($WAUConfig.WAU_UpdatesInterval -eq "Daily") {
        $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUConfig.WAU_UpdatesAtTime
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiDaily") {
        $tasktriggers += New-ScheduledTaskTrigger -Daily -At $WAUConfig.WAU_UpdatesAtTime -DaysInterval 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "Weekly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "BiWeekly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
    }
    elseif ($WAUConfig.WAU_UpdatesInterval -eq "Monthly") {
        $tasktriggers += New-ScheduledTaskTrigger -Weekly -At $WAUConfig.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
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
        Set-ScheduledTask -TaskPath $WAUTask.TaskPath -TaskName $WAUTask.TaskName -Trigger $taskTriggers | Out-Null
    }

    #Log latest applied config
    Add-Content -Path $GPOLogFile -Value "`nLatest applied settings:"
    $WAUConfig.PSObject.Properties | Where-Object { $_.Name -like "WAU_*" } | Select-Object Name, Value | Out-File -Encoding default -FilePath $GPOLogFile -Append
}

Exit 0
