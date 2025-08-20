#Function to test if a version matches a pinned version pattern

Function Test-PinnedVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentVersion,
        
        [Parameter(Mandatory = $true)]
        [string]$PinnedVersion
    )

    try {
        #Handle exact version match
        if ($PinnedVersion -eq $CurrentVersion) {
            return $true
        }

        #Handle wildcard patterns
        if ($PinnedVersion.Contains("*")) {
            #Replace * with regex pattern and escape dots
            $pattern = [regex]::Escape($PinnedVersion) -replace '\\\*', '.*'
            $pattern = "^$pattern$"
            
            if ($CurrentVersion -match $pattern) {
                return $true
            }
        }

        return $false
    }
    catch {
        Write-ToLog "Error comparing versions '$CurrentVersion' with pattern '$PinnedVersion': $($_.Exception.Message)" "Yellow"
        return $false
    }
}

Function Compare-PinnedVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version1,
        
        [Parameter(Mandatory = $true)]
        [string]$Version2
    )

    try {
        #Split versions into parts
        $v1Parts = $Version1 -split '\.' | ForEach-Object { 
            if ($_ -match '^\d+$') { [int]$_ } else { $_ }
        }
        $v2Parts = $Version2 -split '\.' | ForEach-Object { 
            if ($_ -match '^\d+$') { [int]$_ } else { $_ }
        }

        #Compare each part
        $maxParts = [Math]::Max($v1Parts.Length, $v2Parts.Length)
        
        for ($i = 0; $i -lt $maxParts; $i++) {
            $p1 = if ($i -lt $v1Parts.Length) { $v1Parts[$i] } else { 0 }
            $p2 = if ($i -lt $v2Parts.Length) { $v2Parts[$i] } else { 0 }

            #Handle numeric comparison
            if ($p1 -is [int] -and $p2 -is [int]) {
                if ($p1 -lt $p2) { return -1 }
                if ($p1 -gt $p2) { return 1 }
            }
            else {
                #String comparison for non-numeric parts
                $comparison = [string]::Compare($p1, $p2)
                if ($comparison -ne 0) { return $comparison }
            }
        }

        return 0 #Versions are equal
    }
    catch {
        Write-ToLog "Error comparing versions '$Version1' and '$Version2': $($_.Exception.Message)" "Yellow"
        return 0
    }
}

Function Test-ShouldPin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentVersion,
        
        [Parameter(Mandatory = $true)]
        [string]$PinnedVersion
    )

    try {
        #For wildcard patterns, check if current version is within the pattern
        if ($PinnedVersion.Contains("*")) {
            return (Test-PinnedVersion -CurrentVersion $CurrentVersion -PinnedVersion $PinnedVersion)
        }
        
        #For exact versions, check if current version is less than or equal to pinned version
        $comparison = Compare-PinnedVersion -Version1 $CurrentVersion -Version2 $PinnedVersion
        
        #Pin if current version is less than or equal to the pinned version
        return ($comparison -le 0)
    }
    catch {
        Write-ToLog "Error determining if $AppId should be pinned: $($_.Exception.Message)" "Yellow"
        return $false
    }
}
