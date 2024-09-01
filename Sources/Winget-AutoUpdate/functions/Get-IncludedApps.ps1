#Function to get the allow List apps

function Get-IncludedApps {
    $AppIDs = @()

    #whitelist in registry
    if ($GPOList) {

        Write-ToLog "-> Included apps from GPO is activated"
        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList").Property
            foreach ($ValueName in $ValueNames) {
                $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList" -Name $ValueName).Trim()
            }
            Write-ToLog "-> Successsfully loaded included apps list."
        }

    }
    #whitelist pulled from URI
    elseif ($URIList) {

        $RegPath = "$WAU_GPORoot";
        $RegValueName = 'WAU_URIList';

        if (Test-Path -Path $RegPath) {
            $RegKey = Get-Item -Path $RegPath;
            $WAUURI = $RegKey.GetValue($RegValueName);
            Write-ToLog "-> Included apps from URI is activated"
            if ($null -ne $WAUURI) {
                $resp = Invoke-WebRequest -Uri $WAUURI -UseDefaultCredentials;
                if ($resp.BaseResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
                    $resp.Content.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries) |
                    ForEach-Object {
                        $AppIds += $_
                    }
                    Write-ToLog "-> Successsfully loaded included apps list."
                }
            }
        }

    }
    #whitelist pulled from local file
    elseif (Test-Path "$WorkingDir\included_apps.txt") {

        $AppIDs = (Get-Content -Path "$WorkingDir\included_apps.txt").Trim()
        Write-ToLog "-> Successsfully loaded local included apps list."

    }

    return $AppIDs | Where-Object { $_.length -gt 0 }

}
