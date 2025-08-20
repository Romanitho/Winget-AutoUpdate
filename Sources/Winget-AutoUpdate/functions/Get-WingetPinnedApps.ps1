#Function to get currently pinned apps from winget

Function Get-WingetPinnedApps {

    try {
        #Get winget pin list
        $pinResult = & $Winget pin list 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ToLog "Error getting winget pin list: $pinResult" "Red"
            return @()
        }

        #Convert output to string and check if pins exist
        $pinOutput = $pinResult | Out-String
        
        #Check if "No pins configured" message or similar
        if ($pinOutput -match "No pins configured" -or $pinOutput -match "No package pins found") {
            Write-ToLog "No apps are currently pinned" "Gray"
            return @()
        }

        #Check if we have valid output with table format
        if (-not ($pinOutput -match "-----")) {
            Write-ToLog "Unexpected winget pin list output format" "Yellow"
            return @()
        }

        #Split output to lines
        $lines = $pinOutput.Split([Environment]::NewLine) | Where-Object { $_ }

        # Find the line that starts with "------" (table separator)
        $headerLine = -1
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i].StartsWith("-----")) {
                $headerLine = $i - 1
                break
            }
        }

        if ($headerLine -eq -1) {
            Write-ToLog "Could not parse winget pin list output" "Yellow"
            return @()
        }

        #Get header titles to determine column positions
        $header = $lines[$headerLine]
        $idStart = $header.IndexOf("Id")
        $versionStart = $header.IndexOf("Version")
        $sourceStart = $header.IndexOf("Source")

        if ($idStart -eq -1 -or $versionStart -eq -1) {
            Write-ToLog "Could not determine column positions in winget pin output" "Yellow"
            return @()
        }

        $pinnedApps = @()
        
        # Parse data lines (after the separator line)
        for ($i = $headerLine + 2; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            
            #Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                #Extract columns based on positions
                $appId = ""
                $version = ""
                
                if ($versionStart -lt $line.Length) {
                    $appId = $line.Substring($idStart, $versionStart - $idStart).Trim()
                    
                    if ($sourceStart -ne -1 -and $sourceStart -lt $line.Length) {
                        $version = $line.Substring($versionStart, $sourceStart - $versionStart).Trim()
                    }
                    else {
                        $version = $line.Substring($versionStart).Trim()
                    }
                }
                else {
                    $appId = $line.Substring($idStart).Trim()
                    $version = ""
                }

                if (-not [string]::IsNullOrWhiteSpace($appId)) {
                    $pinnedApp = [PSCustomObject]@{
                        AppId = $appId
                        Version = $version
                    }
                    $pinnedApps += $pinnedApp
                    Write-ToLog "Found pinned app: $appId = $version" "Gray"
                }
            }
            catch {
                Write-ToLog "Error parsing pin line: $line - $($_.Exception.Message)" "Yellow"
            }
        }

        if ($pinnedApps.Count -gt 0) {
            Write-ToLog "Found $($pinnedApps.Count) currently pinned app(s)" "Green"
        }

        return $pinnedApps
    }
    catch {
        Write-ToLog "Error retrieving pinned apps: $($_.Exception.Message)" "Red"
        return @()
    }
}
