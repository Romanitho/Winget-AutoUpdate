#Function to get the Block List apps

function Get-ExcludedMajorUpdateApps {

    $AppIDs = @()

    #blacklist major updates in registry
    if ($GPOList) {

        Write-ToLog "-> Excluded major update apps from GPO is activated"
        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\MajorUpdateBlackList") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\MajorUpdateBlackList").Property
            foreach ($ValueName in $ValueNames) {
                $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\MajorUpdateBlackList" -Name $ValueName).Trim()
            }
            Write-ToLog "-> Successsfully loaded major update excluded apps list."
        }

    }
    #blacklist major updates pulled from URI
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
    #blacklist major updates pulled from local file
    elseif (Test-Path "$WorkingDir\excluded_major_updates_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\excluded_major_updates_apps.txt").Trim()
        Write-ToLog "-> Successsfully loaded local excluded major update apps list."

    }
    #blacklist major updates pulled from default file
    elseif (Test-Path "$WorkingDir\config\default_excluded_major_updates_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\config\default_excluded_major_updates_apps.txt").Trim()
        Write-ToLog "-> Successsfully loaded default excluded major update apps list."

    }

    return $AppIDs | Where-Object { $_.length -gt 0 }
}
