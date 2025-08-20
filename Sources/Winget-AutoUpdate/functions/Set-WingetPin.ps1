#Function to set winget pin for an application

Function Set-WingetPin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $false)]
        [string]$Source = "winget"
    )

    try {
        Write-ToLog "Setting pin for $AppId to version $Version..." "DarkYellow"
        
        #Execute winget pin add command
        $pinResult = & $Winget pin add --id $AppId --version $Version --source $Source 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-ToLog "Successfully pinned $AppId to version $Version" "Green"
            return $true
        }
        else {
            #Check if pin already exists
            $resultString = $pinResult | Out-String
            if ($resultString -match "already pinned" -or $resultString -match "Pin already exists") {
                Write-ToLog "$AppId is already pinned (existing pin will be respected)" "Yellow"
                return $true
            }
            else {
                Write-ToLog "Failed to pin $AppId : $resultString" "Red"
                return $false
            }
        }
    }
    catch {
        Write-ToLog "Error setting pin for ${AppId}: $($_.Exception.Message)" "Red"
        return $false
    }
}

Function Remove-WingetPin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $false)]
        [string]$Source = "winget"
    )

    try {
        Write-ToLog "Removing pin for $AppId..." "DarkYellow"
        
        #Execute winget pin remove command
        $unpinResult = & $Winget pin remove --id $AppId --source $Source 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-ToLog "Successfully removed pin for $AppId" "Green"
            return $true
        }
        else {
            $resultString = $unpinResult | Out-String
            Write-ToLog "Failed to remove pin for $AppId : $resultString" "Red"
            return $false
        }
    }
    catch {
        Write-ToLog "Error removing pin for ${AppId}: $($_.Exception.Message)" "Red"
        return $false
    }
}

Function Sync-WingetPins {
    param(
        [Parameter(Mandatory = $true)]
        [array]$DesiredPins,
        
        [Parameter(Mandatory = $false)]
        [string]$Source = "winget"
    )

    try {
        #Get currently pinned apps
        $currentPins = Get-WingetPinnedApps
        
        $pinsAdded = 0
        $pinsSkipped = 0
        
        #Add new pins from GPO
        foreach ($desiredPin in $DesiredPins) {
            $existingPin = $currentPins | Where-Object { $_.AppId -eq $desiredPin.AppId }
            
            if ($existingPin) {
                Write-ToLog "$($desiredPin.AppId) is already pinned to version '$($existingPin.Version)' - respecting existing pin" "Yellow"
                $pinsSkipped++
            }
            else {
                if (Set-WingetPin -AppId $desiredPin.AppId -Version $desiredPin.Version -Source $Source) {
                    $pinsAdded++
                }
            }
        }
        
        if ($pinsAdded -gt 0) {
            Write-ToLog "Applied $pinsAdded new pin(s) from GPO configuration" "Green"
        }
        
        if ($pinsSkipped -gt 0) {
            Write-ToLog "Skipped $pinsSkipped app(s) that were already pinned" "Gray"
        }
        
        return $true
    }
    catch {
        Write-ToLog "Error syncing winget pins: $($_.Exception.Message)" "Red"
        return $false
    }
}
