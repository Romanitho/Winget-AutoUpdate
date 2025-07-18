#Function to check Block/Allow List External Path for Dual Listing Mode

function Test-DualListPath ($ListPath, $WingetUpdatePath) {
    $Results = @{
        WhiteListUpdated = $false
        BlackListUpdated = $false
        Success = $true
    }

    # Process both included_apps.txt and excluded_apps.txt
    $ListTypes = @("included_apps.txt", "excluded_apps.txt")
    
    foreach ($ListType in $ListTypes) {
        # Get local and external list paths
        $LocalList = -join ($WingetUpdatePath, "\", $ListType)
        $ExternalList = -join ($ListPath, "\", $ListType)

        # Check if a list exists
        $dateLocal = $null
        if (Test-Path "$LocalList") {
            $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }

        # If path is URL
        if ($ListPath -like "http*") {
            $ExternalList = -join ($ListPath, "/", $ListType)

            # Test if $ListPath contains the character "?" (testing for SAS token)
            if ($ListPath -match "\?") {
                # Split the URL into two strings at the "?" substring
                $splitPath = $ListPath.Split("`?")

                # Assign the first string (up to "?") to the variable $resourceURI
                $resourceURI = $splitPath[0]

                # Assign the second string (after "?" to the end) to the variable $sasToken
                $sasToken = $splitPath[1]

                # Join the parts and add "/$ListType?" in between the parts
                $ExternalList = -join ($resourceURI, "/$ListType`?", $sasToken)
            }

            $wc = New-Object System.Net.WebClient
            try {
                $wc.OpenRead("$ExternalList").Close() | Out-Null
                $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
                if ($dateExternal -and $dateExternal -gt $dateLocal) {
                    try {
                        $wc.DownloadFile($ExternalList, $LocalList)
                        if ($ListType -eq "included_apps.txt") {
                            $Results.WhiteListUpdated = $true
                        } else {
                            $Results.BlackListUpdated = $true
                        }
                    }
                    catch {
                        $Results.Success = $false
                        Write-ToLog "Error downloading $ListType from $ExternalList" "Red"
                    }
                }
            }
            catch {
                # File doesn't exist remotely, continue processing
                Write-ToLog "$ListType not found at $ExternalList (this is normal if only one list type is used)" "Yellow"
            }
        }
        # If path is UNC or local
        else {
            if (Test-Path -Path $ExternalList -PathType leaf -ErrorAction SilentlyContinue) {
                $dateExternal = (Get-Item "$ExternalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                if ($dateExternal -gt $dateLocal) {
                    try {
                        Copy-Item $ExternalList -Destination $LocalList -Force -ErrorAction Stop
                        if ($ListType -eq "included_apps.txt") {
                            $Results.WhiteListUpdated = $true
                        } else {
                            $Results.BlackListUpdated = $true
                        }
                    }
                    catch {
                        $Results.Success = $false
                        Write-ToLog "Error copying $ListType from $ExternalList" "Red"
                    }
                }
            }
            else {
                # File doesn't exist, continue processing
                Write-ToLog "$ListType not found at $ExternalList (this is normal if only one list type is used)" "Yellow"
            }
        }
    }

    return $Results
}
