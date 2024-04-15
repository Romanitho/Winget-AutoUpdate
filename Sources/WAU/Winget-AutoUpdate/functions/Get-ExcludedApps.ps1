#Function to get the Block List apps

function Get-ExcludedApps {

    $AppIDs = @()

    #region blacklist in registry
    if ($GPOList) {

        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList").Property

            foreach ($ValueName in $ValueNames) {
                $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList" -Name $ValueName).Trim()
            }

        }

    }     
    #endregion blacklist in registry
    #region blacklist pulled from URI
    elseif ($URIList) {

        $RegPath = "$WAU_GPORoot";
        $RegValueName = 'WAU_URIList';
        
        if (Test-Path -Path $RegPath) {
            $RegKey = Get-Item -Path $RegPath;
            $WAUURI = $RegKey.GetValue($RegValueName);
            if ($null -ne $WAUURI) {
                $resp = Invoke-WebRequest -Uri $WAUURI -UseDefaultCredentials;
                if ($resp.BaseResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
                    $resp.Content.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries) | 
                    ForEach-Object {
                        $AppIds += $_
                    }
                }
            }
        }

    }
    #endregion blacklist pulled from URI
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        return (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

    return $AppIDs | Where-Object { $_.length -gt 0 }
}
