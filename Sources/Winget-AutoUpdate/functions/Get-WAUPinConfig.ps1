#Function to get WAU pin configuration from various sources

Function Get-WAUPinConfig {

    class PinConfig {
        [string]$Id
        [string]$Version
        [string]$Source
    }

    $pinConfigs = @()

    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"

    try {
        Write-ToLog "Loading WAU pin configuration..." "Yellow"

        # Check if pin management is enabled
        if ($WAUConfig.WAU_EnablePinManagement -ne 1) {
            Write-ToLog "WAU Pin Management is disabled" "Gray"
            return @()
        }

        # 1. Check GPO policies first (highest priority)
        if ($WAUConfig.WAU_ActivateGPOManagement -eq 1) {
            Write-ToLog "Checking GPO for pin configuration..." "Gray"
            
            try {
                $GPOPins = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps" -ErrorAction SilentlyContinue
                
                if ($GPOPins) {
                    $GPOPins.PSObject.Properties | ForEach-Object {
                        if ($_.Name -notlike "PS*") {  # Skip PowerShell properties
                            $pinConfig = [PinConfig]::new()
                            $pinConfig.Id = $_.Name
                            $pinConfig.Version = $_.Value
                            $pinConfig.Source = "GPO"
                            $pinConfigs += $pinConfig
                            Write-ToLog "  GPO Pin: $($_.Name) = $($_.Value)" "Gray"
                        }
                    }
                }
            }
            catch {
                Write-ToLog "No GPO pin configuration found" "Gray"
            }
        }

        # 2. Check external pin path (if configured and no GPO pins)
        if ($pinConfigs.Count -eq 0 -and $WAUConfig.WAU_PinnedAppsPath) {
            $PinnedAppsPathClean = $($WAUConfig.WAU_PinnedAppsPath.TrimEnd(" ", "\", "/"))
            Write-ToLog "Checking external pin path: $PinnedAppsPathClean" "Gray"
            
            try {
                if ($PinnedAppsPathClean -like "http*") {
                    # Download from URL
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    Invoke-WebRequest -Uri $PinnedAppsPathClean -OutFile $tempFile -UseBasicParsing
                    $pinContent = Get-Content $tempFile -ErrorAction SilentlyContinue
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
                else {
                    # Read from local/network path
                    $pinFilePath = Join-Path $PinnedAppsPathClean "pinned_apps.txt"
                    if (Test-Path $pinFilePath) {
                        $pinContent = Get-Content $pinFilePath -ErrorAction SilentlyContinue
                    }
                }
                
                if ($pinContent) {
                    foreach ($line in $pinContent) {
                        $line = $line.Trim()
                        if ($line -and !$line.StartsWith("#") -and $line.Contains("=")) {
                            $parts = $line.Split("=", 2)
                            if ($parts.Length -eq 2) {
                                $pinConfig = [PinConfig]::new()
                                $pinConfig.Id = $parts[0].Trim()
                                $pinConfig.Version = $parts[1].Trim()
                                $pinConfig.Source = "External"
                                $pinConfigs += $pinConfig
                                Write-ToLog "  External Pin: $($pinConfig.Id) = $($pinConfig.Version)" "Gray"
                            }
                        }
                    }
                }
            }
            catch {
                Write-ToLog "Error reading external pin configuration: $($_.Exception.Message)" "Red"
            }
        }

        # 3. Check local pin configuration file (lowest priority)
        if ($pinConfigs.Count -eq 0) {
            $localPinFile = Join-Path $WorkingDir "pinned_apps.txt"
            Write-ToLog "Checking local pin file: $localPinFile" "Gray"
            
            if (Test-Path $localPinFile) {
                try {
                    $pinContent = Get-Content $localPinFile -ErrorAction SilentlyContinue
                    
                    foreach ($line in $pinContent) {
                        $line = $line.Trim()
                        if ($line -and !$line.StartsWith("#") -and $line.Contains("=")) {
                            $parts = $line.Split("=", 2)
                            if ($parts.Length -eq 2) {
                                $pinConfig = [PinConfig]::new()
                                $pinConfig.Id = $parts[0].Trim()
                                $pinConfig.Version = $parts[1].Trim()
                                $pinConfig.Source = "Local"
                                $pinConfigs += $pinConfig
                                Write-ToLog "  Local Pin: $($pinConfig.Id) = $($pinConfig.Version)" "Gray"
                            }
                        }
                    }
                }
                catch {
                    Write-ToLog "Error reading local pin configuration: $($_.Exception.Message)" "Red"
                }
            }
        }

        if ($pinConfigs.Count -gt 0) {
            Write-ToLog "Loaded $($pinConfigs.Count) pin configurations" "Green"
        }
        else {
            Write-ToLog "No pin configurations found" "Gray"
        }

        return $pinConfigs

    }
    catch {
        Write-ToLog "Error loading pin configuration: $($_.Exception.Message)" "Red"
        return @()
    }
}

Function Apply-WAUPinConfig {
    
    Param(
        [Parameter(Mandatory=$true)]
        [array]$PinConfigs
    )

    # Initialize logging if not already set
    Initialize-WAULogging -LogFileName "pin-operations.log"

    try {
        if ($PinConfigs.Count -eq 0) {
            Write-ToLog "No pin configurations to apply" "Gray"
            return $true
        }

        Write-ToLog "Applying $($PinConfigs.Count) pin configurations..." "Yellow"
        
        $successCount = 0
        $failCount = 0

        foreach ($pinConfig in $PinConfigs) {
            $success = Set-WingetPin -Id $pinConfig.Id -Version $pinConfig.Version -Action "Add"
            
            if ($success) {
                $successCount++
            }
            else {
                $failCount++
            }
        }

        Write-ToLog "Pin application completed: $successCount successful, $failCount failed" "Green"
        
        return ($failCount -eq 0)

    }
    catch {
        Write-ToLog "Error applying pin configurations: $($_.Exception.Message)" "Red"
        return $false
    }
}
