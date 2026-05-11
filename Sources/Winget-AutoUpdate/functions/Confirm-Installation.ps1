<#
.SYNOPSIS
    Verifies application installation at expected version.

.PARAMETER AppName
    WinGet package identifier.

.PARAMETER AppVer
    Expected version prefix.

.PARAMETER src
    The WinGet source to query (e.g. "winget", "msstore"). Defaults to
    "winget".

.OUTPUTS
    Boolean: True if installed at version.
#>
Function Confirm-Installation ($AppName, $AppVer, $src = "winget") {
    if ([string]::IsNullOrWhiteSpace($src)) {
        $src = "winget"
    }
    else {
        $src = $src.Trim()
    }

    $JsonFile = "$env:TEMP\InstalledApps.json"
    & $Winget export -s $src -o $JsonFile --include-versions | Out-Null

    $Packages = (Get-Content $JsonFile -Raw | ConvertFrom-Json).Sources.Packages
    $match = $Packages | Where-Object { $_.PackageIdentifier -eq $AppName -and $_.Version -like "$AppVer*" }

    return [bool]$match
}
