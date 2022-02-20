<#
.SYNOPSIS
Update Winget-AutoUpdate with customisations.

.DESCRIPTION
Run the scheduled task only when idle and only once per day
https://github.com/AdamBearWA/Winget-AutoUpdate

.EXAMPLE
.\Winget-AutoUpdate-Customisations.ps1
#>

[CmdletBinding()]
param(
)

<# FUNCTIONS #>

function Update-WingetAutoUpdate{
    try{
        #Check if previous version location exists and delete
        $task = Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue

        if ($task) {
            # Settings for the scheduled task for Updates
            $taskTrigger = New-ScheduledTaskTrigger -Daily -At 6AM
            $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00 -RunOnlyIfIdle

            # Update the scheduled task
            Set-ScheduledTask -TaskName 'Winget-AutoUpdate' -Settings $taskSettings -Trigger $taskTrigger

            Write-host "`nInstallation succeeded!" -ForegroundColor Green
        } else {
            Write-host "`nInstallation failed! Make sure Winget-AutoUpdate has installed successfully before running this script." -ForegroundColor Red
            return $False
        }

        Start-sleep 1
    }
    catch{
        Write-host "`nInstallation failed! Run me with admin rights." -ForegroundColor Red
        Start-sleep 1
        return $False
    }
}

<# MAIN #>

Write-host "###################################"
Write-host "#                                 #"
Write-host "#        Winget AutoUpdate        #"
Write-host "#          Customisations         #"
Write-host "#                                 #"
Write-host "###################################`n"
Write-host "Applying customisations..."

Update-WingetAutoUpdate

Start-Sleep 3