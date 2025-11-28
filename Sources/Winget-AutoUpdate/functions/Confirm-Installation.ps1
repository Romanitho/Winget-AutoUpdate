<#
.SYNOPSIS
    Verifies application installation at expected version.

.PARAMETER AppName
    WinGet package identifier.

.PARAMETER AppVer
    Expected version prefix.

.OUTPUTS
    Boolean: True if installed at version.
#>
Function Confirm-Installation ($AppName, $AppVer) {

    $JsonFile = "$env:TEMP\InstalledApps.json"
    & $Winget export -s winget -o $JsonFile --include-versions | Out-Null

    $Packages = (Get-Content $JsonFile -Raw | ConvertFrom-Json).Sources.Packages
    $match = $Packages | Where-Object { $_.PackageIdentifier -eq $AppName -and $_.Version -like "$AppVer*" }

    return [bool]$match
}
