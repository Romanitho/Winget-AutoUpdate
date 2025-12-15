<#
.SYNOPSIS
    Compares two semantic version strings.

.DESCRIPTION
    Compares two version strings following semantic versioning rules.
    Handles pre-release versions (e.g., "1.0.0-beta1").
    Pre-release versions are considered less than their release counterparts.

.PARAMETER Version1
    The first version string to compare.

.PARAMETER Version2
    The second version string to compare.

.OUTPUTS
    Integer: -1 if Version1 < Version2, 0 if equal, 1 if Version1 > Version2

.EXAMPLE
    Compare-SemVer -Version1 "1.0.0" -Version2 "1.1.0"  # Returns -1

.EXAMPLE
    Compare-SemVer -Version1 "2.0.0" -Version2 "2.0.0-beta"  # Returns 1
#>
function Compare-SemVer {
    param (
        [string]$Version1,
        [string]$Version2
    )

    # Split version and pre-release parts (e.g., "1.0.0-beta1" -> ["1.0.0", "beta1"])
    $v1Parts = $Version1 -split '-'
    $v2Parts = $Version2 -split '-'

    # Parse main version numbers
    $v1 = [Version]$v1Parts[0]
    $v2 = [Version]$v2Parts[0]

    # Compare major version
    if ($v1.Major -ne $v2.Major) {
        return [Math]::Sign($v1.Major - $v2.Major)
    }

    # Compare minor version
    if ($v1.Minor -ne $v2.Minor) {
        return [Math]::Sign($v1.Minor - $v2.Minor)
    }

    # Compare build version
    if ($v1.Build -ne $v2.Build) {
        return [Math]::Sign($v1.Build - $v2.Build)
    }

    # Compare revision
    if ($v1.Revision -ne $v2.Revision) {
        return [Math]::Sign($v1.Revision - $v2.Revision)
    }

    # Handle pre-release comparison
    if ($v1Parts.Length -eq 2 -and $v2Parts.Length -eq 2) {
        # Both have pre-release tags, compare them lexically
        return [String]::Compare($v1Parts[1], $v2Parts[1])
    }
    elseif ($v1Parts.Length -eq 2) {
        # Version1 has pre-release, Version2 doesn't (pre-release < release)
        return -1
    }
    elseif ($v2Parts.Length -eq 2) {
        # Version2 has pre-release, Version1 doesn't (release > pre-release)
        return 1
    }

    # Versions are equal
    return 0
}