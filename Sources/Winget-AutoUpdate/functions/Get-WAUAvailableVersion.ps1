<#
.SYNOPSIS
    Retrieves the latest available version of WAU from GitHub.

.DESCRIPTION
    Queries the GitHub API to determine the latest available version
    of Winget-AutoUpdate. Supports both stable releases and pre-releases
    based on configuration.

.OUTPUTS
    String containing the version number (without 'v' prefix).

.EXAMPLE
    $version = Get-WAUAvailableVersion

.NOTES
    Requires WAUConfig with WAU_UpdatePrerelease setting.
    Falls back to web scraping if API fails.
#>
function Get-WAUAvailableVersion {

    # Check if pre-release versions should be considered
    if ($WAUConfig.WAU_UpdatePrerelease -eq 1) {

        Write-ToLog "WAU AutoUpdate Pre-release versions is Enabled" "Cyan"

        try {
            # Query GitHub API for all releases (pre-releases included)
            $WAUurl = "https://api.github.com/repos/Romanitho/$($GitHub_Repo)/releases"
            $WAUAvailableVersion = ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
        }
        catch {
            # Fallback: Parse version from GitHub releases page
            $url = "https://github.com/Romanitho/$($GitHub_Repo)/releases"
            $link = ((Invoke-WebRequest $url -UseBasicParsing).Links.href -match "/$($GitHub_Repo)/releases/tag/v*")[0]
            $WAUAvailableVersion = $link.Trim().Split("v")[-1]
        }

    }
    else {

        try {
            # Query GitHub API for latest stable release only
            $WAUurl = "https://api.github.com/repos/Romanitho/$($GitHub_Repo)/releases/latest"
            $WAUAvailableVersion = ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
        }
        catch {
            # Fallback: Parse version from GitHub releases page
            $url = "https://github.com/Romanitho/$($GitHub_Repo)/releases/latest"
            $link = ((Invoke-WebRequest $url -UseBasicParsing).Links.href -match "/$($GitHub_Repo)/releases/tag/v*")[0]
            $WAUAvailableVersion = $link.Trim().Split("v")[-1]
        }

    }

    return $WAUAvailableVersion

}
