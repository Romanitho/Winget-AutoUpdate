#Function to get the Block List apps

function Get-ExcludedApps {

    if ($GPOList) {

        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {

            $Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList\'

            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList").Property

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
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        return (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
