# Function to test a version against a version pattern with wildcards
function Test-VersionPattern {
    param (
        [string]$Version,
        [string]$VersionPattern
    )

    # Escape special regex characters in the version pattern, except for '*'
    $EscapedPattern = $VersionPattern -replace '([\\.\+\(\)\{\}\[\]\^\$\|])', '\$1'
    # Replace the wildcard with a regex wildcard
    $RegexPattern = $EscapedPattern -replace '\*', '.*'

    # Match the version against the regex pattern
    if ($Version -match "^$RegexPattern$") {
        return $true
    } else {
        return $false
    }
}