<#
.SYNOPSIS
    Exports a list of system-installed WinGet applications.

.DESCRIPTION
    Retrieves the list of applications installed in the system context
    and saves their package identifiers to a configuration file. This
    list is used to exclude system apps from user-context updates.

.PARAMETER src
    The WinGet source repository name to query.

.EXAMPLE
    Get-WingetSystemApps -src "winget"

.NOTES
    Output file: $WorkingDir\config\winget_system_apps.txt
    Used by Get-WingetOutdatedApps to filter user-context updates.
#>
function Get-WingetSystemApps {
    Param(
        [Parameter(Position = 0, Mandatory = $True, HelpMessage = "You MUST supply value for winget repo, we need it")]
        [ValidateNotNullorEmpty()]
        [string]$src
    )

    # Output file for system apps list
    $jsonFile = "$WorkingDir\config\winget_system_apps.txt"

    # Export installed apps from WinGet to JSON format
    & $Winget export -o $jsonFile --accept-source-agreements -s $src | Out-Null

    # Parse JSON and extract package identifiers
    $InstalledApps = get-content $jsonFile | ConvertFrom-Json

    # Write app identifiers to text file
    Set-Content $InstalledApps.Sources.Packages.PackageIdentifier -Path $jsonFile

    # Sort the list for consistency
    Get-Content $jsonFile | Sort-Object | Set-Content $jsonFile

}
