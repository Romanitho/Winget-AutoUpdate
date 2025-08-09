#Function to manage winget pins (add/remove)

Function Set-WingetPin {
    
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Version,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Add", "Remove")]
        [string]$Action = "Add"
    )
    
    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"
    
    try {
        if ($Action -eq "Add") {
            if ($Version) {
                Write-ToLog "Adding pin for $Id to version $Version..." "Yellow"
                $result = & $Winget pin add --id $Id --version $Version 2>&1
            }
            else {
                Write-ToLog "Adding pin for $Id to current installed version..." "Yellow"
                $result = & $Winget pin add --id $Id 2>&1
            }
        }
        elseif ($Action -eq "Remove") {
            Write-ToLog "Removing pin for $Id..." "Yellow"
            $result = & $Winget pin remove --id $Id 2>&1
        }
        
        # Check if command was successful
        if ($LASTEXITCODE -eq 0) {
            Write-ToLog "Pin operation completed successfully for $Id" "Green"
            return $true
        }
        else {
            Write-ToLog "Pin operation failed for $Id. Error: $($result -join ' ')" "Red"
            return $false
        }
    }
    catch {
        Write-ToLog "Error managing pin for $Id`: $($_.Exception.Message)" "Red"
        return $false
    }
}

Function Remove-AllWingetPins {
    
    Param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"
    
    try {
        Write-ToLog "Removing all winget pins..." "Yellow"
        
        if ($Force) {
            $result = & $Winget pin reset --force 2>&1
        }
        else {
            $result = & $Winget pin reset 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-ToLog "All pins removed successfully" "Green"
            return $true
        }
        else {
            Write-ToLog "Failed to remove all pins. Error: $($result -join ' ')" "Red"
            return $false
        }
    }
    catch {
        Write-ToLog "Error removing all pins: $($_.Exception.Message)" "Red"
        return $false
    }
}

Function Test-WingetPinSupport {
    
    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"
    
    try {
        # Test if winget pin command is available
        $result = & $Winget pin --help 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-ToLog "Winget pin support is available" "Green"
            return $true
        }
        else {
            Write-ToLog "Winget pin support is not available in this version" "Red"
            return $false
        }
    }
    catch {
        Write-ToLog "Error testing winget pin support: $($_.Exception.Message)" "Red"
        return $false
    }
}
