<#
.SYNOPSIS
    Writes pending update data to disk and triggers the user-facing update prompt.

.DESCRIPTION
    Serializes the list of pending apps and reminder config into pending-updates.json,
    then fires the Winget-AutoUpdate-UpdatePrompt scheduled task which presents the
    WPF deadline dialog to the logged-in user.

    This function is fire-and-forget -- it returns immediately after starting the task.
    The caller should not poll for task completion.

    The JSON payload format:
        {
          "Config": { "ReminderIntervalDays": 2 },
          "Apps": [
            { "Name": "...", "Id": "...", "Version": "...", "AvailableVersion": "...", "Deadline": "yyyy-MM-dd" },
            ...
          ]
        }

.PARAMETER PendingApps
    Array of PSCustomObjects, each with:
        Name             [string] - Display name of the application
        Id               [string] - Winget package identifier
        Version          [string] - Currently installed version
        AvailableVersion [string] - Available version to install
        Deadline         [string] - Deadline date as "yyyy-MM-dd" string

    The caller is responsible for enriching deadline entries with Name and Version
    from the Get-WingetOutdatedApps result before calling this function.

.PARAMETER ReminderIntervalDays
    Number of days to snooze when the user dismisses the dialog.
    Written into the JSON Config envelope so the prompt script does not
    need to independently re-read WAU configuration.
#>
function Start-UpdatePromptTask {

    param(
        [Parameter(Mandatory = $true)]
        [array]$PendingApps,

        [Parameter(Mandatory = $true)]
        [int]$ReminderIntervalDays,

        [Parameter(Mandatory = $false)]
        [string]$CompanyName = ''
    )

    $ConfigDir = Join-Path $WAUConfig.InstallLocation "config"
    $JsonPath  = Join-Path $ConfigDir "pending-updates.json"

    # Build the payload. @($PendingApps) forces array serialization in JSON
    # even when only a single app is pending.
    $payload = [PSCustomObject]@{
        Config = [PSCustomObject]@{
            ReminderIntervalDays = $ReminderIntervalDays
            CompanyName          = $CompanyName
        }
        Apps = @($PendingApps)
    }

    try {
        $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $JsonPath -Encoding UTF8 -Force
        Write-ToLog "Pending updates written: $($PendingApps.Count) apps - $JsonPath"
    }
    catch {
        Write-ToLog "ERROR: Could not write pending-updates.json -- $($_.Exception.Message)" "Red"
        return
    }

    # Trigger the UpdatePrompt task. This runs WAU-UpdatePrompt.ps1 via ServiceUI.exe
    # in the logged-in user's desktop session. The main task exits immediately after.
    $promptTask = Get-ScheduledTask -TaskName "Winget-AutoUpdate-UpdatePrompt" -ErrorAction SilentlyContinue
    if ($promptTask) {
        $promptTask | Start-ScheduledTask
        Write-ToLog "Winget-AutoUpdate-UpdatePrompt task triggered"
    }
    else {
        Write-ToLog "WARNING: Winget-AutoUpdate-UpdatePrompt task not found -- update prompt will not be shown" "Yellow"
    }
}
