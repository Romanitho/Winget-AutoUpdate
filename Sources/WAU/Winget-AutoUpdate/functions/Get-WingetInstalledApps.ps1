function Get-WingetInstalledApps {

    #Json File, where to export system installed apps
    $jsonFile = "$env:TEMP\winget_installed_apps.txt"

    Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue

    #Get list of installed Winget apps to json file
    & $Winget export -o $jsonFile --accept-source-agreements --include-versions -s winget | Out-Null

    #Convert json file to txt file with app ids
    $InstalledApps = Get-Content $jsonFile | ConvertFrom-Json

    function _version {
        # convert given version string to format x.x.x.x by adding trailing zeros
        param ($version)

        if ($version -notlike "*.*") {
            Write-Warning "$version is not in the correct format."
            return $version
        }

        $dotCount = $version.split('.').count - 1

        switch ($dotCount) {
            0 {
                return "$version.0.0.0"
            }

            1 {
                return "$version.0.0"

            }

            2 {
                return "$version.0"

            }

            3 {
                return $version
            }
        }
    }

    $InstalledApps.Sources.Packages | % {
        [PSCustomObject]@{
            Id      = $_.PackageIdentifier
            Version = (_version $_.Version)
        }
    }

}