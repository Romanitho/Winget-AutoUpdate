<#
.SYNOPSIS
    Writes pending update data to disk and triggers the user-facing update prompt.

.DESCRIPTION
    Serializes the list of pending apps and reminder config into pending-updates.json,
    then launches the WPF prompt in the exact interactive session that owns the
    WPF deadline dialog to the logged-in user.

    This function is fire-and-forget -- it returns immediately after starting the prompt.
    The caller should not poll for task completion.

    The JSON payload format:
        {
          "Config": { "ReminderIntervalHours": 2, "ReminderIntervalDays": 1, "CompanyName": "" },
          "Apps": [
            { "Name": "...", "Id": "...", "Version": "...", "AvailableVersion": "...", "Deadline": "yyyy-MM-dd HH:mm:ss" },
            ...
          ]
        }

.PARAMETER PendingApps
    Array of PSCustomObjects, each with:
        Name             [string] - Display name of the application
        Id               [string] - Winget package identifier
        Version          [string] - Currently installed version
        AvailableVersion [string] - Available version to install
        Deadline         [string] - Deadline date as "yyyy-MM-dd HH:mm:ss" string

    The caller is responsible for enriching deadline entries with Name and Version
    from the Get-WingetOutdatedApps result before calling this function.

.PARAMETER ReminderIntervalHours
    Number of hours to snooze when the user dismisses the dialog.
    Written into the JSON Config envelope so the prompt script does not
    need to independently re-read WAU configuration.
#>
function Start-UpdatePromptTask {

    param(
        [Parameter(Mandatory = $true)]
        [array]$PendingApps,

        [Parameter(Mandatory = $true)]
        [int]$ReminderIntervalHours,

        [Parameter(Mandatory = $false)]
        [string]$CompanyName = '',
        [string]$UserSid = '',
        [bool]$InventoryComplete = $true
    )

    $ConfigDir = Join-Path $WAUConfig.InstallLocation "config"
    $JsonPath  = Join-Path $ConfigDir "pending-updates.json"

    # Build the payload. @($PendingApps) forces array serialization in JSON
    # even when only a single app is pending.
    $payload = [PSCustomObject]@{
        Config = [PSCustomObject]@{
            ReminderIntervalHours = $ReminderIntervalHours
            ReminderIntervalDays  = [math]::Max(1, [int][math]::Round($ReminderIntervalHours / 24))
            CompanyName           = $CompanyName
            UserSid               = $UserSid
            InventoryComplete     = $InventoryComplete
        }
        Apps = @($PendingApps)
    }

    try {
        Write-WauAtomicJson -Path $JsonPath -Value $payload
        Write-ToLog "Pending updates written: $($PendingApps.Count) apps - $JsonPath"
    }
    catch {
        Write-ToLog "ERROR: Could not write pending-updates.json -- $($_.Exception.Message)" "Red"
        return
    }

    # Launch the prompt in the exact session that owns the scanned user SID.
    # The process remains SYSTEM-owned; ServiceUI only bridges session isolation.
    $targetSession = Get-WauInteractiveSessionId -UserSid $UserSid
    if (-not $targetSession) {
        Write-ToLog "ERROR: No unambiguous active session found for $UserSid; update prompt was not launched." 'Red'
        return
    }

    $promptCommand = "& '$([System.IO.Path]::Combine($Script:WorkingDir, 'WAU-UpdatePrompt.ps1'))'"
    $encodedPrompt = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($promptCommand))
    $powershell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    try {
        if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq $targetSession) {
            Start-Process -FilePath $powershell `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -EncodedCommand $encodedPrompt" `
                -WorkingDirectory $Script:WorkingDir -ErrorAction Stop | Out-Null
        }
        else {
            $serviceUI = Join-Path $Script:WorkingDir 'ServiceUI.exe'
            if (-not (Test-Path -LiteralPath $serviceUI -PathType Leaf)) { throw 'ServiceUI.exe is missing.' }
            Start-Process -FilePath $serviceUI `
                -ArgumentList "-nowait -session:$targetSession $powershell -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -EncodedCommand $encodedPrompt" `
                -WorkingDirectory $Script:WorkingDir -ErrorAction Stop | Out-Null
        }
        Write-ToLog "Update prompt launched in session $targetSession"
    }
    catch {
        Write-ToLog "ERROR: Update prompt could not be launched in session $targetSession -- $($_.Exception.Message)" 'Red'
    }
}
