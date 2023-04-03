#Function to get the allow List apps

function Get-IncludedApps {

    if ($GPOList) {

        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList") {

            $Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList\'

            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList").Property

            foreach ($ValueName in $ValueNames) {
                $AppIDs = [Microsoft.Win32.Registry]::GetValue($Key, $ValueName, $false)
                [PSCustomObject]@{
                    Value = $ValueName
                    Data  = $AppIDs.Trim()
                }
            }

        }
        return $AppIDs

    }
    elseif (Test-Path "$WorkingDir\included_apps.txt") {

        return (Get-Content -Path "$WorkingDir\included_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
