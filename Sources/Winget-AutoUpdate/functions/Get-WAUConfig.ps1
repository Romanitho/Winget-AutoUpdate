#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    try {
        #Get WAU Configurations from install config
        $WAUConfig_64_86 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate*", "HKLM:\SOFTWARE\WOW6432Node\Romanitho\Winget-AutoUpdate*" -ErrorAction SilentlyContinue | Sort-Object { $_.ProductVersion } -Descending
        $WAUConfig = $WAUConfig_64_86[0]
        
        # If no config found, create a default one
        if (-not $WAUConfig) {
            $WAUConfig = [PSCustomObject]@{
                InstallLocation = "C:\Program Files\WAU"
                WAU_UseDualListing = 0
                WAU_UseWhiteList = 0
                ProductVersion = "1.0.0"
            }
        }

        #Check if GPO Management is enabled
        try {
            $ActivateGPOManagement = Get-ItemPropertyValue "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_ActivateGPOManagement" -ErrorAction SilentlyContinue
        }
        catch {
            $ActivateGPOManagement = $null
        }

        #If GPO Management is enabled, replace settings
        if ($ActivateGPOManagement -eq 1) {
            try {
                #Get all WAU Policies
                $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

                #Replace loaded configurations by ones from Policies
                if ($WAUPolicies) {
                    $WAUPolicies.PSObject.Properties | ForEach-Object {
                        if ($_.Name -notmatch "^PS") {  # Skip PowerShell built-in properties
                            $WAUConfig.PSObject.Properties.add($_)
                        }
                    }
                }
            }
            catch {
                # If GPO policies can't be read, continue with existing config
                Write-Warning "Could not read GPO policies, using existing configuration"
            }
        }

        #Return config
        return $WAUConfig
    }
    catch {
        # If everything fails, return a minimal default config
        Write-Warning "Could not read WAU configuration, using default values"
        return [PSCustomObject]@{
            InstallLocation = "C:\Program Files\WAU"
            WAU_UseDualListing = 0
            WAU_UseWhiteList = 0
            ProductVersion = "1.0.0"
        }
    }
}
