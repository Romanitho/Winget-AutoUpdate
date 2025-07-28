#Function to synchronize Winget Pins with WAU Configuration

function Sync-WingetPins {
    # Get current Winget pins
    $WingetPins = & $Winget pin list | ConvertFrom-String -PropertyNames "AppID", "Version" | Where-Object {$_.AppID}

    # Get WAU pinned apps
    $WAUPinnedApps = Get-PinnedApps

    # Remove Winget pins that are no longer in WAU config
    foreach ($WingetPin in $WingetPins) {
        if (-not $WAUPinnedApps.ContainsKey($WingetPin.AppID)) {
            Write-ToLog "-> Removing Winget pin for $($WingetPin.AppID)" "Yellow"
            & $Winget pin remove $WingetPin.AppID
        }
    }

    # Add Winget pins based on WAU config
    foreach ($AppID in $WAUPinnedApps.Keys) {
        $WAUPinnedApp = $WAUPinnedApps[$AppID]
        $Version = $WAUPinnedApp.Version

        # Check if Winget pin already exists
        $ExistingWingetPin = $WingetPins | Where-Object {$_.AppID -eq $AppID}

        if (-not $ExistingWingetPin) {
            # Add Winget pin
            if ($Version -eq "current") {
                Write-ToLog "-> Adding Winget pin for $($AppID) to current version" "Yellow"
                # Get current version
                $AppInfo = & $Winget show --id $AppID -e --accept-source-agreements -s winget | Out-String
                if ($AppInfo -match "Version: (.+)") {
                    $CurrentVersion = $Matches[1].Trim()
                    & $Winget pin add $AppID -v $CurrentVersion
                } else {
                    Write-ToLog "-> Could not determine current version for $($AppID), skipping pin" "Red"
                }
            } else {
                Write-ToLog "-> Adding Winget pin for $($AppID) to version '$Version'" "Yellow"
                & $Winget pin add $AppID -v $Version
            }
        }
    }
}