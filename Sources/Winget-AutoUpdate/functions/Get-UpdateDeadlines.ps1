<#
.SYNOPSIS
    Reads update deadline tracking entries from the WAU registry.

.DESCRIPTION
    Returns all deadline entries stored under the WAU UpdateDeadlines registry key.
    When OutdatedApps is provided, entries for apps no longer in the outdated list
    are purged (the app self-updated or was removed). Entries with corrupt or
    unparseable date values are also purged with a warning.

.PARAMETER OutdatedApps
    Array of current outdated app objects from Get-WingetOutdatedApps.
    When provided, any registry entry whose AppId is NOT in this list is deleted.
    Omit this parameter to read entries without any purge logic.

.OUTPUTS
    Array of PSCustomObjects with properties:
        AppId            [string]   - Winget package identifier
        FirstDetected    [DateTime] - Date the update was first detected
        Deadline         [DateTime] - Date by which the update must be installed
        AvailableVersion [string]   - Available version at time of last detection
#>
function Get-UpdateDeadlines {

    param(
        [Parameter(Mandatory = $false)]
        [array]$OutdatedApps
    )

    $DeadlineRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines"
    $deadlines = @()

    if (-not (Test-Path $DeadlineRegPath)) {
        return $deadlines
    }

    $entries = Get-ChildItem -Path $DeadlineRegPath -ErrorAction SilentlyContinue
    if (-not $entries) {
        return $deadlines
    }

    # Build an explicit ID set for purge comparison. Using a hashtable avoids
    # any subtle issues with Where-Object pipeline on JSON-deserialized objects.
    $outdatedIdSet = $null
    if ($PSBoundParameters.ContainsKey('OutdatedApps')) {
        $outdatedIdSet = @{}
        foreach ($oa in $OutdatedApps) {
            if ($oa.Id) { $outdatedIdSet[$oa.Id] = $true }
        }
    }

    foreach ($entry in $entries) {

        $appId = $entry.PSChildName

        # When OutdatedApps is supplied, purge entries for apps that are no longer outdated.
        # This covers apps the user updated manually outside of WAU.
        if ($null -ne $outdatedIdSet) {
            if (-not $outdatedIdSet.ContainsKey($appId)) {
                Write-ToLog "Deadline purged (app no longer outdated): $appId"
                Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                continue
            }
        }

        $props = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
        if (-not $props) {
            Write-ToLog "Deadline purged (unreadable registry entry): $appId" "Yellow"
            Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        # Parse dates safely. Corrupt values are logged and the entry is purged
        # so a clean entry will be re-created on the next WAU run.
        $firstDetected = $null
        $deadline = $null

        try {
            $firstDetected = [DateTime]::Parse($props.FirstDetected)
        }
        catch {
            Write-ToLog "WARNING: Unparseable FirstDetected for $appId ('$($props.FirstDetected)')" "Yellow"
        }

        try {
            $deadline = [DateTime]::Parse($props.Deadline)
        }
        catch {
            Write-ToLog "WARNING: Unparseable Deadline for $appId ('$($props.Deadline)')" "Yellow"
        }

        if (-not $firstDetected -or -not $deadline) {
            Write-ToLog "Deadline purged (corrupt date values): $appId" "Yellow"
            Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        $deadlines += [PSCustomObject]@{
            AppId            = $appId
            FirstDetected    = $firstDetected
            Deadline         = $deadline
            AvailableVersion = $props.AvailableVersion
        }
    }

    return $deadlines
}
