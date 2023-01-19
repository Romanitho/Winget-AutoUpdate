#Function to get Black List apps

function Get-ExcludedApps {

    if ($GPOList) {
        
        return Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList"
    }
    elseif (Test-Path "$WorkingDir\excluded_apps.txt") {

        return (Get-Content -Path "$WorkingDir\excluded_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
