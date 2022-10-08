function Get-WingetSystemApps {

    #Json File where to export system installed apps
    $jsonFile = "$WorkingDir\winget_system_apps.txt"

    #Get list of installed Winget apps to json file
    & $Winget export -o $jsonFile --accept-source-agreements -s winget | Out-Null

    #Convert json file to txt file with app ids
    $InstalledApps = get-content $jsonFile | ConvertFrom-Json

    #Return app list
    Set-Content $InstalledApps.Sources.Packages.PackageIdentifier -Path $jsonFile

}
