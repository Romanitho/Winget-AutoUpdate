#Function to get GPO-defined pinned apps configuration

Function Get-PinnedApps {

    #Get pinned apps from GPO (if exists)
    $PinnedAppsRegistry = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps" -ErrorAction SilentlyContinue

    if ($PinnedAppsRegistry) {
        #Get all properties except PS* properties
        $PinnedAppsValues = $PinnedAppsRegistry.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }

        $PinnedApps = @()
        foreach ($AppEntry in $PinnedAppsValues) {
            #Parse AppId=Version format
            $AppSpec = $AppEntry.Value
            if ($AppSpec -match "^(.+)=(.+)$") {
                $AppId = $Matches[1].Trim()
                $Version = $Matches[2].Trim()
                
                #Validate version format (basic validation)
                if ($Version -match "^[\d\.\*]+$") {
                    $PinnedApp = [PSCustomObject]@{
                        AppId = $AppId
                        Version = $Version
                    }
                    $PinnedApps += $PinnedApp
                    Write-ToLog "GPO Pin found: $AppId = $Version" "DarkYellow"
                }
                else {
                    Write-ToLog "Invalid version format in GPO pin: $AppSpec" "Red"
                }
            }
            else {
                Write-ToLog "Invalid format in GPO pin (expected AppId=Version): $AppSpec" "Red"
            }
        }

        if ($PinnedApps.Count -gt 0) {
            Write-ToLog "Found $($PinnedApps.Count) pinned app(s) in GPO configuration" "Green"
            return $PinnedApps
        }
    }

    return @()
}
