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
        
        #Execute winget pin add command with timeout
        $timeoutSeconds = 60
        $job = Start-Job -ScriptBlock {
            param($WingetPath, $AppId, $Version, $Source)
            & $WingetPath pin add --id $AppId --version $Version --source $Source 2>&1
        } -ArgumentList $Winget, $AppId, $Version, $Source
        
        $pinResult = $null
        $completed = $false
        $exitCode = 1
        if (Wait-Job $job -Timeout $timeoutSeconds) {
            $pinResult = Receive-Job $job
            if ($job.State -eq 'Completed') {
                $exitCode = 0
            }
            $completed = $true
        }
        else {
            Write-ToLog "Winget pin add command timed out after $timeoutSeconds seconds for $AppId" "Red"
            Stop-Job $job -Force
            Remove-Job $job -Force
            return $false
        }
        
        Remove-Job $job -Force
        
        if (!$completed -or $exitCode -ne 0) {
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
        else {
            Write-ToLog "Successfully pinned $AppId to version $Version" "Green"
            return $true
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
        Write-ToLog "Starting pin synchronization (clean and reset approach)..." "DarkYellow"
        
        #Get currently pinned apps
        $currentPins = Get-WingetPinnedApps
        
        $pinsRemoved = 0
        $pinsAdded = 0
        
        #Remove all existing pins to avoid version mismatch issues
        if ($currentPins -and $currentPins.Count -gt 0) {
            Write-ToLog "Removing $($currentPins.Count) existing pin(s) to ensure clean state..." "DarkYellow"
            foreach ($currentPin in $currentPins) {
                if (Remove-WingetPin -AppId $currentPin.AppId -Source $Source) {
                    $pinsRemoved++
                    Write-ToLog "Removed pin for $($currentPin.AppId)" "Gray"
                }
            }
            Write-ToLog "Removed $pinsRemoved pin(s)" "Green"
        }
        else {
            Write-ToLog "No existing pins to remove" "Gray"
        }
        
        #Apply fresh pins from GPO
        if ($DesiredPins -and $DesiredPins.Count -gt 0) {
            Write-ToLog "Applying $($DesiredPins.Count) pin(s) from GPO configuration..." "DarkYellow"
            foreach ($desiredPin in $DesiredPins) {
                if (Set-WingetPin -AppId $desiredPin.AppId -Version $desiredPin.Version -Source $Source) {
                    $pinsAdded++
                }
            }
            
            if ($pinsAdded -gt 0) {
                Write-ToLog "Successfully applied $pinsAdded pin(s) from GPO configuration" "Green"
            }
        }
        else {
            Write-ToLog "No GPO pins to apply" "Gray"
        }
        
        return $true
    }
    catch {
        Write-ToLog "Error syncing winget pins: $($_.Exception.Message)" "Red"
        return $false
    }
}
