function Get-WingetSystemApps {
Param(
    [Parameter(Position=0,Mandatory=$True,HelpMessage="You MUST supply value for winget repo, we need it")]
    [ValidateNotNullorEmpty()]
    [string]$src
)
    #Json File, where to export system installed apps
    $jsonFile = "$WorkingDir\config\winget_system_apps.txt"

    #Get list of installed Winget apps to json file
    & $Winget export -o $jsonFile --accept-source-agreements -s $src | Out-Null

    #Convert json file to txt file with app ids
    $InstalledApps = get-content $jsonFile | ConvertFrom-Json

    #Save app list
    Set-Content $InstalledApps.Sources.Packages.PackageIdentifier -Path $jsonFile

    #Sort app list
    Get-Content $jsonFile | Sort-Object | Set-Content $jsonFile

}
