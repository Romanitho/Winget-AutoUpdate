#Function to get apps using dual listing mode (both whitelist and blacklist)

function Get-DualListApps {
    param(
        [Parameter(Mandatory = $true)]
        [array]$OutdatedApps
    )

    $IncludedApps = @()
    $ExcludedApps = @()
    $ProcessedApps = @()

    try {
        # Get included apps (whitelist)
        $IncludedApps = Get-IncludedApps
        if (-not $IncludedApps) { $IncludedApps = @() }
    }
    catch {
        Write-ToLog "Warning: Could not load included apps list - $($_.Exception.Message)"
        $IncludedApps = @()
    }

    try {
        # Get excluded apps (blacklist) 
        $ExcludedApps = Get-ExcludedApps
        if (-not $ExcludedApps) { $ExcludedApps = @() }
    }
    catch {
        Write-ToLog "Warning: Could not load excluded apps list - $($_.Exception.Message)"
        $ExcludedApps = @()
    }

    Write-ToLog "Dual listing mode enabled - processing both whitelist and blacklist"
    Write-ToLog "Included apps count: $($IncludedApps.Count)"
    Write-ToLog "Excluded apps count: $($ExcludedApps.Count)"

    # Process each outdated app
    foreach ($app in $OutdatedApps) {
        $appResult = [PSCustomObject]@{
            App = $app
            ShouldUpdate = $false
            Reason = ""
        }

        try {
            # Skip if current app version is unknown
            if ($app.Version -eq "Unknown") {
                $appResult.Reason = "Skipped upgrade because current version is 'Unknown'"
                $ProcessedApps += $appResult
                continue
            }

            # Check if app is in blacklist (exact match)
            if ($ExcludedApps -contains $app.Id) {
                $appResult.Reason = "Skipped upgrade because it is in the excluded app list (blacklist takes precedence)"
                $ProcessedApps += $appResult
                continue
            }

            # Check if app matches blacklist wildcard
            $matchedExcludedWildcard = $ExcludedApps | Where-Object { $app.Id -like $_ }
            if ($matchedExcludedWildcard) {
                $appResult.Reason = "Skipped upgrade because it matches *wildcard* in the excluded app list (blacklist takes precedence)"
                $ProcessedApps += $appResult
                continue
            }

            # If we have a whitelist, check if app is included
            if ($IncludedApps -and $IncludedApps.Count -gt 0) {
                # Check if app is in whitelist (exact match)
                if ($IncludedApps -contains $app.Id) {
                    $appResult.ShouldUpdate = $true
                    $appResult.Reason = "Approved for update - found in whitelist"
                    $ProcessedApps += $appResult
                    continue
                }

                # Check if app matches whitelist wildcard
                $matchedIncludedWildcard = $IncludedApps | Where-Object { $app.Id -like $_ }
                if ($matchedIncludedWildcard) {
                    $appResult.ShouldUpdate = $true
                    $appResult.Reason = "Approved for update - matches *wildcard* in whitelist"
                    $ProcessedApps += $appResult
                    continue
                }

                # App is not in whitelist
                $appResult.Reason = "Skipped upgrade because it is not in the included app list (whitelist)"
                $ProcessedApps += $appResult
            }
            else {
                # No whitelist configured, so update (since it's not in blacklist)
                $appResult.ShouldUpdate = $true
                $appResult.Reason = "Approved for update - not in blacklist and no whitelist configured"
                $ProcessedApps += $appResult
            }
        }
        catch {
            Write-ToLog "Warning: Error processing app $($app.Id) - $($_.Exception.Message)"
            $appResult.Reason = "Error processing app - using safe default (skip)"
            $ProcessedApps += $appResult
        }
    }

    return $ProcessedApps
}
