function Compare-SemVer {
    param (
        [string]$Version1,
        [string]$Version2
    )
    
    # Split version and pre-release parts
    $v1Parts = $Version1 -split '-'
    $v2Parts = $Version2 -split '-'
    
    $v1 = [Version]$v1Parts[0]
    $v2 = [Version]$v2Parts[0]
    
    # Compare main version parts
    if ($v1.Major -ne $v2.Major) {
        return [Math]::Sign($v1.Major - $v2.Major)
    }
    if ($v1.Minor -ne $v2.Minor) {
        return [Math]::Sign($v1.Minor - $v2.Minor)
    }
    if ($v1.Build -ne $v2.Build) {
        return [Math]::Sign($v1.Build - $v2.Build)
    }
    if ($v1.Revision -ne $v2.Revision) {
        return [Math]::Sign($v1.Revision - $v2.Revision)
    }
    
    # Compare pre-release parts if they exist
    if ($v1Parts.Length -eq 2 -and $v2Parts.Length -eq 2) {
        return [String]::Compare($v1Parts[1], $v2Parts[1])
    }
    elseif ($v1Parts.Length -eq 2) {
        return -1
    }
    elseif ($v2Parts.Length -eq 2) {
        return 1
    }
    
    return 0
}