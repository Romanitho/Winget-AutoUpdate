#Function to get the Pinned Apps list

function Get-PinnedApps {
    $PinnedApps = @{}

    #Check if GPO Management is enabled
    $WAUConfig = Get-WAUConfig
    $GPOList = $WAUConfig.WAU_ActivateGPOManagement -eq 1

    #Pinned apps in registry (GPO)
    if ($GPOList) {
        Write-ToLog "-> Pinned apps from GPO is activated"
        if (Test-Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps") {
            $ValueNames = (Get-Item -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps").Property
            foreach ($ValueName in $ValueNames) {
                $PinValue = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\PinnedApps" -Name $ValueName).Trim()
                
                # Parse the pin value (AppID=Version or just AppID)
                if ($PinValue -match "^(.+?)=(.+)$") {
                    $AppID = $matches[1].Trim()
                    $Version = $matches[2].Trim()
                } elseif ($PinValue -match "^(.+)$") {
                    $AppID = $matches[1].Trim()
                    $Version = "current" # Pin to current version
                } else {
                    Write-ToLog "-> Invalid pin format for $ValueName`: $PinValue" "Red"
                    continue
                }
                
                $PinnedApps[$AppID] = @{
                    Version = $Version
                    Source = "GPO"
                }
            }
            Write-ToLog "-> Successfully loaded pinned apps list from GPO."
        }
    }
    #Pinned apps pulled from local file
    elseif (Test-Path "$WorkingDir\pinned_apps.txt") {
        $PinLines = (Get-Content -Path "$WorkingDir\pinned_apps.txt").Trim() | Where-Object { $_.length -gt 0 -and -not $_.StartsWith("#") }
        
        foreach ($PinLine in $PinLines) {
            # Parse the pin line (AppID=Version or just AppID)
            if ($PinLine -match "^(.+?)=(.+)$") {
                $AppID = $matches[1].Trim()
                $Version = $matches[2].Trim()
            } elseif ($PinLine -match "^(.+)$") {
                $AppID = $matches[1].Trim()
                $Version = "current" # Pin to current version
            } else {
                Write-ToLog "-> Invalid pin format in pinned_apps.txt: $PinLine" "Red"
                continue
            }
            
            $PinnedApps[$AppID] = @{
                Version = $Version
                Source = "File"
            }
        }
        Write-ToLog "-> Successfully loaded local pinned apps list."
    }

    return $PinnedApps
}