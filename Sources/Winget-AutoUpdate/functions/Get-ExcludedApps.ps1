#Function to get the Block List apps

function Get-ExcludedApps {

    $AppIDs = @()

    #blacklist in registry
    if ($GPOList) {

        Write-ToLog "-> Excluded apps from GPO is activated"
        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList").Property
            foreach ($ValueName in $ValueNames) {
                $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList" -Name $ValueName).Trim()
            }
            Write-ToLog "-> Successsfully loaded excluded apps list."
        }

    }
    #blacklist pulled from URI
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
                        $AppIds += $_
                    }
                    Write-ToLog "-> Successsfully loaded excluded apps list."
                }
            }
        }

    }
    #blacklist pulled from local file
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim()
        Write-ToLog "-> Successsfully loaded local excluded apps list."

    }
    #blacklist pulled from default file
    elseif (Test-Path "$WorkingDir\config\default_excluded_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\config\default_excluded_apps.txt").Trim()
        Write-ToLog "-> Successsfully loaded default excluded apps list."

    }

    $WAUExcludePinnedApps = $WAUConfig.WAU_ExcludePinnedApps
    if ($WAUExcludePinnedApps -eq 1) {
        #blacklist pinned winget apps
        $pinnedAppsResult = & $Winget pin list | Where-Object { $_ -notlike "   *" } | Out-String
        if (!($pinnedAppsResult -match "-----")) {
            Write-ToLog "-> No pinned winget apps found, nothing to exclude."
        } else {
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
            $index = $lines[$fl] -split '\s{2,}'
            $idStart = $lines[$fl].IndexOf($index[1])
            $versionStart = $lines[$fl].IndexOf($index[2])

            # Now cycle through the real package lines and split accordingly
            For ($i = $fl + 2; $i -lt $lines.Length; $i++) {
                $line = $lines[$i] -replace "[\u2026]", " " # Fix "..." in long names
                if (-Not ($line.StartsWith("-----"))) {

                    # (Alphanumeric | Literal . | Alphanumeric) - the only unique thing in common for lines with applications
                    if ($line -match "\w\.\w") {
                        $softwareId = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
                        if ($null -ne $softwareId) {
                            # Add the extracted software ID to the list
                            $AppIds += $softwareId
                            Write-ToLog "Excluding $softwareId from WAU updates, as this app is pinned in winget"
                        }
                    }
                }
            }
        }
    }
    
    return $AppIDs | Where-Object { $_.length -gt 0 }
}
