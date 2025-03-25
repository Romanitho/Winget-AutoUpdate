#Function to get the Block List apps

function Get-ExcludedApps {

    $AppIDs = @()

    #Blocklist in registry
    if ($GPOList) {

        Write-ToLog "-> Excluded apps from GPO is activated"
        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\Blocklist") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\Blocklist").Property
            foreach ($ValueName in $ValueNames) {
                $AppIDs += [PSCustomObject]@{
                    AppID         = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\Blocklist" -Name $ValueName).Trim()
                    PinnedVersion = $null
                }
            }
            Write-ToLog "-> Successfully loaded excluded apps list."
        }

    }
    #Blocklist pulled from URI
    elseif ($URIList) {

        $RegPath = "$WAU_GPORoot";
        $RegValueName = 'WAU_URIList';

        if (Test-Path -Path $RegPath) {
            $RegKey = Get-Item -Path $RegPath;
            $WAUURI = $RegKey.GetValue($RegValueName);
            Write-ToLog "-> Excluded apps from URI is activated"
            if ($null -ne $WAUURI) {
                $resp = Invoke-WebRequest -Uri $WAUURI -UseDefaultCredentials;
                if ($resp.BaseResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
                    $resp.Content.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries) |
                    ForEach-Object {
                        $AppIDs += [PSCustomObject]@{
                            AppID         = $_
                            PinnedVersion = $null
                        }
                    }
                    Write-ToLog "-> Successfully loaded excluded apps list."
                }
            }
        }

    }
    #Blocklist pulled from local file
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | ForEach-Object {
            [PSCustomObject]@{
                AppID         = $_
                PinnedVersion = $null
            }
        }
        Write-ToLog "-> Successfully loaded local excluded apps list."

    }
    #Blocklist pulled from default file
    elseif (Test-Path "$WorkingDir\config\default_excluded_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\config\default_excluded_apps.txt").Trim() | ForEach-Object {
            [PSCustomObject]@{
                AppID         = $_
                PinnedVersion = $null
            }
        }
        Write-ToLog "-> Successfully loaded default excluded apps list."
    }

    $WAUExcludePinnedApps = $WAUConfig.WAU_ExcludePinnedApps
    if ($WAUExcludePinnedApps -eq 1) {
        # Blacklist pinned winget apps
        $pinnedAppsResult = & $Winget pin list | Where-Object { $_ -notlike "   *" } | Out-String
        if (!($pinnedAppsResult -match "-----")) {
            Write-ToLog "-> No pinned winget apps found, nothing to exclude."
        }
        else {
            Write-ToLog "-> Found pinned winget apps, adding to exclusion now."
            # Split winget output to lines
            $lines = $pinnedAppsResult.Split([Environment]::NewLine) | Where-Object { $_ }

            # Find the line that starts with "------"
            $fl = 0
            while (-not $lines[$fl].StartsWith("-----")) {
                $fl++
            }

            # Get header line
            $fl = $fl - 1

            # Get header titles and calculate start positions of each column
            # Split the header line using a regex that matches one or more spaces or tabs
            $index = $lines[$fl] -split '\s{1,}'

            # Use the index of the second column to find the start positions of each column
            $idStart = $lines[$fl].IndexOf($index[1])
            $versionStart = $lines[$fl].IndexOf($index[2])
            $containsGating = $lines | Where-Object { $_.Trim() -like "*Gating*" }
            if ($containsGating) {
                $pinnedAppVersionStart = $lines[$fl].IndexOf($index[4])
            }

            # Now cycle through the real package lines and split accordingly
            For ($i = $fl + 2; $i -lt $lines.Length; $i++) {
                $line = $lines[$i] -replace "[\u2026]", " " # Fix ellipsis in long names
                if (-Not ($line.StartsWith("-----"))) {

                    # (Alphanumeric | Literal . | Alphanumeric) - the only unique thing in common for lines with applications
                    if ($line -match "\w\.\w") {
                        $softwareId = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()

                        if ($line -like "*Gating*") {
                            # Ensure start index is within bounds
                            if ($pinnedAppVersionStart -lt $line.Length) {
                                $pinnedVersion = $line.Substring($pinnedAppVersionStart).TrimStart() # Get the pinned version
                                $pinnedVersion = $pinnedVersion -replace "^Gating\s+", ""
                                $AdditionalLogText = "with version $pinnedVersion"
                            }
                            else {
                                Write-ToLog "-> Cannot extract pinned app version; invalid start index"
                                $pinnedVersion = $null
                            }
                        }
                        else {
                            $pinnedVersion = $null
                            $AdditionalLogText = $null
                        }

                        if ($null -ne $softwareId) {
                            # Add the extracted software ID and version to the list
                            $AppIDs += [PSCustomObject]@{
                                AppID         = $softwareId
                                PinnedVersion = $pinnedVersion
                            }

                            Write-ToLog "-> Excluding $softwareId from WAU updates, as this app is pinned in winget $AdditionalLogText"
                        }
                    }
                }
            }
        }
    }

    return $AppIDs | Where-Object { $_.AppID -and $_.AppID.length -gt 0 }
}
