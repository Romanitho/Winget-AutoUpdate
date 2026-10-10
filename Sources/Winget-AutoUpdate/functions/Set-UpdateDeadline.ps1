<#
.SYNOPSIS
    Creates or updates a deadline registry entry for a pending app update.

.DESCRIPTION
    For apps with no existing entry: creates a new entry with FirstDetected set to
    the current timestamp, Deadline set to now + DeadlineHours, and AvailableVersion from the app.

    For apps with an existing entry: updates AvailableVersion only if a newer version
    is now available. The original FirstDetected and Deadline are always preserved --
    the deadline clock never resets due to a version bump.

.PARAMETER App
    PSCustomObject with at minimum: Id [string], AvailableVersion [string].
    This is the standard object shape returned by Get-WingetOutdatedApps.

.PARAMETER DeadlineHours
    Number of hours from first detection until the update is forced.
    Sourced from WAU_UpdateDeadlineHours policy/config.
#>
function Set-UpdateDeadline {

    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$App,

        [Parameter(Mandatory = $true)]
        [int]$DeadlineHours,

        [Parameter(Mandatory = $false)]
        [string]$DeadlineRegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines'
    )
    $AppRegPath = Get-WauDeadlineRegistryPath -App $App -DeadlineRegPath $DeadlineRegPath

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

        # New entry -- set the deadline clock from now
        $now      = Get-Date
        $deadline = $now.AddHours($DeadlineHours)

        Set-WauDeadlineLeafValues -Path $AppRegPath -App $App -FirstDetected $now -Deadline $deadline -AvailableVersion $App.AvailableVersion

        Write-ToLog "Deadline entry created: $($App.Id) -- due $($deadline.ToString('yyyy-MM-dd HH:mm')) ($DeadlineHours hours)"
    }
    Set-ItemProperty -LiteralPath $AppRegPath -Name PackageId -Value $App.Id
    Set-ItemProperty -LiteralPath $AppRegPath -Name Source -Value $(if ($App.Source) { $App.Source } else { 'winget' })
    Set-ItemProperty -LiteralPath $AppRegPath -Name Scope -Value $App.Scope
    Set-ItemProperty -LiteralPath $AppRegPath -Name UserSid -Value ([string]$App.UserSid)
    Set-ItemProperty -LiteralPath $AppRegPath -Name IdentityKey -Value (Get-WauAppKey $App)
}
