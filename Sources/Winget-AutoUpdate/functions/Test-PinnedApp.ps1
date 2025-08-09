#Function to test if an app is pinned and if the available version should be skipped

function Test-PinnedApp {
    param (
        [string]$AppId,
        [string]$AvailableVersion
    )

    $PinnedApps = Get-PinnedApps
    
    if (-not $PinnedApps.ContainsKey($AppId)) {
        # App is not pinned
        return @{ ShouldSkip = $false }
    }

    $PinInfo = $PinnedApps[$AppId]
    $PinnedVersion = $PinInfo.Version

    if ($PinnedVersion -eq "current") {
        # App is pinned to current version, skip updates
        return @{ ShouldSkip = $true; PinnedVersion = "current" }
    }

    if ($PinnedVersion -match "\*") {
        # Wildcard version pattern
        # Load helper function to compare version patterns
        . "$WorkingDir\functions\Test-VersionPattern.ps1"

        if (Test-VersionPattern -Version $AvailableVersion -VersionPattern $PinnedVersion) {
             # Available version matches the pattern, allow update
            return @{ ShouldSkip = $false; PinnedVersion = $PinnedVersion }
        } else {
            # Available version does not match the pattern, skip update
            return @{ ShouldSkip = $true; PinnedVersion = $PinnedVersion }
        }
    } else {
        # Specific version, skip updates
        return @{ ShouldSkip = $true; PinnedVersion = $PinnedVersion }
    }
}