#Function to get White List apps

function Get-IncludedApps {

    if ($GPOList) {

        return Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList"

    }
    elseif (Test-Path "$WorkingDir\included_apps.txt") {

        return (Get-Content -Path "$WorkingDir\included_apps.txt").Trim() | Where-Object { $_.length -gt 0 }

    }

}
