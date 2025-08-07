#Function to get the Block List apps

function Get-ExcludedApps {

    $AppIDs = @()

    #blacklist in Policies registry
    if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList") {
        Write-ToLog "-> Excluded apps from GPO is activated"
        $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList").Property
        foreach ($ValueName in $ValueNames) {
            $AppIDs += (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList" -Name $ValueName).Trim()
        }
        foreach ($app in $AppIDs) {
            Write-ToLog "Exclude app $app"
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

    return $AppIDs | Where-Object { $_.length -gt 0 }
}
