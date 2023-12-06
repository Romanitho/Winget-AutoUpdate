Function Confirm-Installation ($AppName, $AppVer) {

    #Set json export file
    $JsonFile = "$env:TEMP\InstalledApps.json"

    #Get installed apps and version in json file
    & $Winget export -s winget -o $JsonFile --include-versions | Out-Null

    #Get json content
    $Json = Get-Content $JsonFile -Raw | ConvertFrom-Json

    #Get apps and version in hashtable
    $Packages = $Json.Sources.Packages

    # Search for specific app and version
    $Apps = $Packages | Where-Object { $_.PackageIdentifier -eq $AppName -and $_.Version -like "$AppVer*" }

    if ($Apps) {
        return $true
    }
    else {
        return $false
    }
}