#Function to get the Block List apps

function Get-ExcludedApps {

    if ($GPOList) {

        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {

            $Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList\'

            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList").Property

            $AppIDs = @()

            foreach ($ValueName in $ValueNames) {
                $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList" -Name $ValueName)
            }

        }
        return $AppIDs | Where-Object { $_.length -gt 0 }

    }
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        return (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
