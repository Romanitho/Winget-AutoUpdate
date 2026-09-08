<#
.SYNOPSIS
    Installs pending updates selected by the user via the WAU deadline prompt.

.DESCRIPTION
    Runs in SYSTEM context as the Winget-AutoUpdate-UpdateNow scheduled task.
    Triggered when the user clicks "Update Now" in the WAU deadline prompt dialog.

    Reads the list of apps to update from config\pending-updates.json (written by
    the main WAU task), processes each app through WAU's standard Update-App pipeline
    (which handles retries, mods, and per-app notifications), then cleans up registry
    deadline entries for apps that were successfully updated.

    Initialization mirrors Winget-Upgrade.ps1 so that Update-App and its dependencies
    (Start-NotifTask, Write-ToLog, Confirm-Installation, etc.) have all required
    script-scoped variables in scope.

.NOTES
    Scheduled task: Winget-AutoUpdate-UpdateNow
    Run as:         SYSTEM (S-1-5-18), RunLevel Highest
    Trigger:        On demand (started by WAU-UpdatePrompt.ps1)
    Instances:      IgnoreNew (only one instance at a time)
#>

#region LOAD FUNCTIONS
[string]$Script:WorkingDir = $PSScriptRoot

Get-ChildItem -Path "$Script:WorkingDir\functions" -File -Filter "*.ps1" -Depth 0 |
    ForEach-Object { . $_.FullName }
#endregion LOAD FUNCTIONS

#region INITIALIZATION
$null = & "$env:WINDIR\System32\cmd.exe" /c ""
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

[string]$LogFile = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'updates.log')
#endregion INITIALIZATION

#region CONTEXT AND CONFIG
[bool]$Script:IsSystem = $true

Write-ToLog -LogMsg "USER-INITIATED UPDATE" -IsHeader

$Script:WAUConfig = Get-WAUConfig

[string]$Script:WingetSourceCustom = 'winget'
if ($null -ne $Script:WAUConfig.WAU_WingetSourceCustom) {
    $Script:WingetSourceCustom = $Script:WAUConfig.WAU_WingetSourceCustom.Trim()
}

[string]$LocaleDisplayName = Get-NotifLocale
Write-ToLog "Notification Level: $($Script:WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan"
#endregion CONTEXT AND CONFIG

#region WINGET
[string]$Script:Winget = Get-WingetCmd

if (-not $Script:Winget) {
    Write-ToLog "Critical: Winget not found -- cannot process updates" "Red"
    Exit 1
}

Write-ToLog "Selected winget instance: $Script:Winget"
#endregion WINGET

#region READ PENDING UPDATES
$JsonPath = [System.IO.Path]::Combine($Script:WorkingDir, 'config', 'pending-updates.json')

if (-not (Test-Path $JsonPath)) {
    Write-ToLog "No pending-updates.json found -- nothing to update" "Cyan"
    Exit 0
}

try {
    $pendingData = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-ToLog "ERROR: Could not parse pending-updates.json -- $($_.Exception.Message)" "Red"
    Exit 1
}

if (-not $pendingData.Apps -or @($pendingData.Apps).Count -eq 0) {
    Write-ToLog "pending-updates.json contains no apps -- nothing to update" "Cyan"
    Remove-Item -Path $JsonPath -Force -ErrorAction SilentlyContinue
    Exit 0
}

Write-ToLog "$(@($pendingData.Apps).Count) apps queued for update"
#endregion READ PENDING UPDATES

#region PROCESS UPDATES
$Script:InstallOK = 0
$DeadlineRegBase  = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines"

# Split apps by scope -- user-scoped apps must be updated in user context.
$machineApps = @($pendingData.Apps | Where-Object { $_.Scope -ne 'user' })
$userApps    = @($pendingData.Apps | Where-Object { $_.Scope -eq 'user' })

if ($machineApps.Count -gt 0) {
    Write-ToLog "$($machineApps.Count) machine-scoped apps to update"
    foreach ($app in $machineApps) {
        Write-ToLog "-> $($app.Name) : $($app.Version) -> $($app.AvailableVersion)"

        Update-App $app -src $Script:WingetSourceCustom

        if (Confirm-Installation $app.Id $app.AvailableVersion $Script:WingetSourceCustom) {
            $AppRegPath = Join-Path $DeadlineRegBase $app.Id
            if (Test-Path $AppRegPath) {
                Remove-Item -Path $AppRegPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "Deadline entry purged (update confirmed): $($app.Id)"
            }
        }
        else {
            Write-ToLog "$($app.Name) : update could not be confirmed -- deadline entry preserved for next run" "Yellow"
        }
    }
}

# User-scoped apps: hand off to user context task for update.
# Deadline entries are cleaned up on the next SYSTEM cycle when the app
# no longer appears in user-context-outdated.csv (self-healing).
if ($userApps.Count -gt 0) {
    if ($Script:WAUConfig.WAU_UserContext -eq 1) {
        $userUpdateDir = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate')
        if (-not (Test-Path $userUpdateDir)) { New-Item -ItemType Directory -Path $userUpdateDir -Force | Out-Null }
        $userUpdatePath = [System.IO.Path]::Combine($userUpdateDir, 'user-context-update.json')
        try {
            ConvertTo-Json -InputObject @($userApps) -Depth 3 | Set-Content -Path $userUpdatePath -Encoding UTF8 -Force
            Write-ToLog "$($userApps.Count) user-scoped apps written to user-context-update.json"

            $userContextTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -ErrorAction SilentlyContinue
            if ($userContextTask) {
                $userContextTask | Start-ScheduledTask
                Write-ToLog "UserContext task triggered for user-scoped updates"
            }
            else {
                Write-ToLog "WARNING: UserContext task not found -- user-scoped apps will not be updated" "Yellow"
            }
        }
        catch {
            Write-ToLog "ERROR: Could not write user-context-update.json -- $($_.Exception.Message)" "Red"
        }
    }
    else {
        Write-ToLog "$($userApps.Count) user-scoped apps skipped (WAU_UserContext not enabled)" "Yellow"
    }
}
#endregion PROCESS UPDATES

#region CLEANUP
Remove-Item -Path $JsonPath -Force -ErrorAction SilentlyContinue
Write-ToLog "pending-updates.json removed"

if ($Script:InstallOK -gt 0) {
    Write-ToLog "$Script:InstallOK apps successfully updated" "Green"
}
else {
    Write-ToLog "No apps were successfully updated" "Yellow"
}

Write-ToLog "End of user-initiated update" "Cyan"
Start-Sleep 3
#endregion CLEANUP
