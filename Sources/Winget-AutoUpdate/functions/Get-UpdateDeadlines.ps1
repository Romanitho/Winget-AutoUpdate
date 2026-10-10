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
        [array]$OutdatedApps,

        [Parameter(Mandatory = $false)]
        [string]$DeadlineRegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines'
    )
    $deadlines = @()

    if (-not (Test-Path $DeadlineRegPath)) {
        return $deadlines
    }

    $entries = Get-ChildItem -Path $DeadlineRegPath -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $values = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $values.FirstDetected -and $values.Deadline
    }
    if (-not $entries) {
        return $deadlines
    }

    # Build an explicit ID set for purge comparison. Using a hashtable avoids
    # any subtle issues with Where-Object pipeline on JSON-deserialized objects.
    $outdatedIdSet = $null
    if ($PSBoundParameters.ContainsKey('OutdatedApps')) {
        $outdatedIdSet = @{}
        foreach ($oa in $OutdatedApps) {
            if ($oa.Id) { $outdatedIdSet[(Get-WauAppKey $oa)] = $true }
        }
    }

    foreach ($entry in $entries) {

        $props = Get-ItemProperty -Path $entry.PSPath -ErrorAction SilentlyContinue
        $appId = if ($props.IdentityKey) { [string]$props.IdentityKey } else { [string]$entry.PSChildName }

        # When OutdatedApps is supplied, purge entries for apps that are no longer outdated.
        # This covers apps the user updated manually outside of WAU.
        if ($null -ne $outdatedIdSet) {
            if (-not $outdatedIdSet.ContainsKey($appId)) {
                Write-ToLog "Deadline purged (app no longer outdated): $appId"
                if ($props.PackageId -and $props.Scope) { Remove-WauUpdateDeadline -App $props -DeadlineRegPath $DeadlineRegPath }
                else { Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
                continue
            }
        }

        if (-not $props) {
            Write-ToLog "Deadline purged (unreadable registry entry): $appId" "Yellow"
            Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        # Parse dates safely. Corrupt values are logged and the entry is purged
        # so a clean entry will be re-created on the next WAU run.
        $firstDetected = $null
        $deadline = $null

        [string[]]$dateFormats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd')
        try {
            $firstDetected = [DateTime]::ParseExact($props.FirstDetected, $dateFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
        }
        catch {
            Write-ToLog "WARNING: Unparseable FirstDetected for $appId ('$($props.FirstDetected)')" "Yellow"
        }

        try {
            $deadline = [DateTime]::ParseExact($props.Deadline, $dateFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
        }
        catch {
            Write-ToLog "WARNING: Unparseable Deadline for $appId ('$($props.Deadline)')" "Yellow"
        }

        if (-not $firstDetected -or -not $deadline) {
            Write-ToLog "Deadline purged (corrupt date values): $appId" "Yellow"
            if ($props.PackageId -and $props.Scope) { Remove-WauUpdateDeadline -App $props -DeadlineRegPath $DeadlineRegPath }
            else { Remove-Item -Path $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
            continue
        }

        $deadlines += [PSCustomObject]@{
            AppId            = $appId
            Id               = $props.PackageId
            PackageId        = $props.PackageId
            Source           = $props.Source
            Scope            = $props.Scope
            UserSid          = $props.UserSid
            IdentityKey      = $appId
            FirstDetected    = $firstDetected
            Deadline         = $deadline
            AvailableVersion = $props.AvailableVersion
        }
    }

    return $deadlines
}
