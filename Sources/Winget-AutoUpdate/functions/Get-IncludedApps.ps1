#Function to get the allow List apps

function Get-IncludedApps {

    $AppIDs = @()

    #whitelist in Policies registry
    if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") {
        Write-ToLog "-> Included apps from GPO is activated"
        $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList").Property
        foreach ($ValueName in $ValueNames) {
            $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList" -Name $ValueName).Trim()
        }
        foreach ($app in $AppIDs) {
            Write-ToLog "Include app $app"
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
