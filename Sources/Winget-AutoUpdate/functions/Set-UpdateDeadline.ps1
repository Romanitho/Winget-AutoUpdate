<#
.SYNOPSIS
    Creates or updates a deadline registry entry for a pending app update.

.DESCRIPTION
    For apps with no existing entry: creates a new entry with FirstDetected set to
    today, Deadline set to today + DeadlineDays, and AvailableVersion from the app.

    For apps with an existing entry: updates AvailableVersion only if a newer version
    is now available. The original FirstDetected and Deadline are always preserved --
    the deadline clock never resets due to a version bump.

.PARAMETER App
    PSCustomObject with at minimum: Id [string], AvailableVersion [string].
    This is the standard object shape returned by Get-WingetOutdatedApps.

.PARAMETER DeadlineDays
    Number of days from first detection until the update is forced.
    Sourced from WAU_UpdateDeadlineDays policy/config.
#>
function Set-UpdateDeadline {

    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$App,

        [Parameter(Mandatory = $true)]
        [int]$DeadlineDays
    )

    $DeadlineRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines"
    $AppRegPath = Join-Path $DeadlineRegPath $App.Id

    # Ensure the parent key exists
    if (-not (Test-Path $DeadlineRegPath)) {
        New-Item -Path $DeadlineRegPath -Force | Out-Null
    }

    if (Test-Path $AppRegPath) {

        # Entry exists -- update AvailableVersion when it changes.
        # FirstDetected and Deadline are intentionally preserved (deadline never resets).
        $existing = Get-ItemProperty -Path $AppRegPath -ErrorAction SilentlyContinue
        if ($existing.AvailableVersion -ne $App.AvailableVersion) {
            Set-ItemProperty -Path $AppRegPath -Name "AvailableVersion" -Value $App.AvailableVersion
            Write-ToLog "Deadline entry updated (new version): $($App.Id) -- $($existing.AvailableVersion) -> $($App.AvailableVersion)"
        }

    }
    else {

        # New entry -- set the deadline clock from today
        $today    = (Get-Date).Date
        $deadline = $today.AddDays($DeadlineDays)

        New-Item -Path $AppRegPath -Force | Out-Null
        Set-ItemProperty -Path $AppRegPath -Name "FirstDetected"    -Value $today.ToString("yyyy-MM-dd")
        Set-ItemProperty -Path $AppRegPath -Name "Deadline"         -Value $deadline.ToString("yyyy-MM-dd")
        Set-ItemProperty -Path $AppRegPath -Name "AvailableVersion" -Value $App.AvailableVersion

        Write-ToLog "Deadline entry created: $($App.Id) -- due $($deadline.ToString('yyyy-MM-dd')) ($DeadlineDays days)"
    }
}
