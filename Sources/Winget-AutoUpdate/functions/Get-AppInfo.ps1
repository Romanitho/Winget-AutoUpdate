<#
.SYNOPSIS
    Retrieves application release notes URL from WinGet.

.DESCRIPTION
    Queries WinGet for application metadata and extracts the
    release notes URL if available.

.PARAMETER AppID
    The WinGet package identifier to query.

.OUTPUTS
    String containing the release notes URL, or empty if not found.

.EXAMPLE
    $releaseUrl = Get-AppInfo "Microsoft.PowerShell"

.NOTES
    Uses WinGet show command with source agreements accepted.
#>
Function Get-AppInfo ($AppID) {

    # Query WinGet for application details
    $String = & $winget show $AppID --accept-source-agreements -s winget | Out-String

    # Extract Release Notes URL using regex
    $ReleaseNote = [regex]::match($String, "(?<=Release Notes Url: )(.*)(?=\n)").Groups[0].Value

    return $ReleaseNote
}
