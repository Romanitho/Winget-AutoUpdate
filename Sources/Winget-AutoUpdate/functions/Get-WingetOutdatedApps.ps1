<#
.SYNOPSIS
    Retrieves the list of applications with available updates from WinGet.

.DESCRIPTION
    Queries WinGet for applications with available updates and returns
    a structured list. Parses WinGet's tabular output and handles
    non-Latin characters and text formatting issues.

.PARAMETER src
    The WinGet source repository name to query (e.g., "winget").

.OUTPUTS
    Array of Software objects with Name, Id, Version, and AvailableVersion.
    Returns descriptive string if no updates are found.

.EXAMPLE
    $outdated = Get-WingetOutdatedApps -src "winget"

.NOTES
    Excludes system-installed apps when running in user context.
    Results are randomized to prevent update ordering bias.
#>
function Get-WingetOutdatedApps {

    Param(
        [Parameter(Position = 0, Mandatory = $True, HelpMessage = "You MUST supply value for winget repo, we need it")]
        [ValidateNotNullorEmpty()]
        [string]$src
    )

    # Define class for structured output
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    # Get upgrade list from WinGet
    try {
        $upgradeResult = & $Winget upgrade --source $src | Where-Object { $_ -notlike "   *" } | Out-String
    }
    catch {
        Write-ToLog "Error while receiving winget upgrade list: $_" "Red"
        $upgradeResult = $null
    }

    # Check if output contains valid data (header separator line)
    if (!($upgradeResult -match "-----")) {
        return "No update found. 'Winget upgrade' output:`n$upgradeResult"
    }
    else {

        # Split output into lines, removing empty lines
        $lines = $upgradeResult.Split([Environment]::NewLine) | Where-Object { $_ }

        # Find the separator line (starts with "-----")
        $fl = 0
        while (-not $lines[$fl].StartsWith("-----")) {
            $fl++
        }

        # Get header line (one line before separator)
        $fl = $fl - 1

        # Split header into columns (preserving trailing spaces for positioning)
        $index = $lines[$fl] -split '(?<=\s)(?!\s)'

        # Calculate column positions (handle non-Latin characters by replacing with **)
        $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
        $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
        $availableStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length

        # Parse each data line
        $upgradeList = @()
        For ($i = $fl + 2; $i -lt $lines.Length; $i++) {
            # Fix ellipsis character in long names
            $line = $lines[$i] -replace "[\u2026]", " "

            # Handle multiple tables (new header encountered)
            if ($line.StartsWith("-----")) {
                $fl = $i - 1
                $index = $lines[$fl] -split '(?<=\s)(?!\s)'
                $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
                $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
                $availableStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length
            }

            # Check if line contains an application entry (has format word.word)
            if ($line -match "\w\.\w") {
                $software = [Software]::new()

                # Calculate name declination for non-Latin character handling
                $nameDeclination = $($line.Substring(0, $idStart) -replace '[\u4e00-\u9fa5]', '**').Length - $line.Substring(0, $idStart).Length
                $software.Name = $line.Substring(0, $idStart - $nameDeclination).TrimEnd()
                $software.Id = $line.Substring($idStart - $nameDeclination, $versionStart - $idStart).TrimEnd()
                $software.Version = $line.Substring($versionStart - $nameDeclination, $availableStart - $versionStart).TrimEnd()
                $software.AvailableVersion = $line.Substring($availableStart - $nameDeclination).TrimEnd()

                $upgradeList += $software
            }
        }

        # In user context, filter out system-installed apps
        if ($IsSystem -eq $false) {
            $SystemApps = Get-Content -Path "$WorkingDir\config\winget_system_apps.txt" -ErrorAction SilentlyContinue
            $upgradeList = $upgradeList | Where-Object { $SystemApps -notcontains $_.Id }
        }

        # Return randomized list to prevent update ordering bias
        return $upgradeList | Sort-Object { Get-Random }

    }

}
