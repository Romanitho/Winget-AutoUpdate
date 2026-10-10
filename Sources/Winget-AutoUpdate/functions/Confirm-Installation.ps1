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
Function Confirm-Installation ($AppName, $AppVer, $src = "winget", $Scope) {
    if ($Scope) {
        if ($Scope -notin @('user', 'machine')) { return $false }
        $arguments = @('list', '--id', $AppName, '--exact', '--source', $src,
            '--scope', $Scope, '--accept-source-agreements', '--disable-interactivity')
        $details = Test-WauWingetDetails
        if ($details) { $arguments += '--details' }
        $result = Invoke-WauWinget -Arguments $arguments
        if ($result.ExitCode -ne 0) { return $false }
        $installed = if ($details) { @(ConvertFrom-WauWingetDetails $result.Output -Source $src) }
                     else { @(ConvertFrom-WauWingetTable $result.Output) }
        return [bool]($installed | Where-Object { $_.Id -eq $AppName -and (Test-WauSameVersion $_.Version $AppVer) })
    }
    if ([string]::IsNullOrWhiteSpace($src)) {
        $src = "winget"
    }
    else {
        $src = $src.Trim()
    }

    $JsonFile = "$env:TEMP\InstalledApps.json"
    & $Winget export -s $src -o $JsonFile --include-versions | Out-Null

    $Packages = (Get-Content $JsonFile -Raw | ConvertFrom-Json).Sources.Packages
    $match = $Packages | Where-Object { $_.PackageIdentifier -eq $AppName -and ($_.Version -like "$AppVer*" -or (Test-WauSameVersion $_.Version $AppVer)) }

    return [bool]$match
}

