#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Get WAU Configurations from install config
    $WAUConfig_64_86 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate*", "HKLM:\SOFTWARE\WOW6432Node\Romanitho\Winget-AutoUpdate*" -ErrorAction SilentlyContinue | Sort-Object { $_.ProductVersion } -Descending
    $WAUConfig = $WAUConfig_64_86[0]

    #Check if GPO Management is enabled
    $ActivateGPOManagement = Get-ItemPropertyValue "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_ActivateGPOManagement" -ErrorAction SilentlyContinue

    #If GPO Management is enabled, replace settings
    if ($ActivateGPOManagement -eq 1) {

        #Get all WAU Policies
        $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

        #Replace loaded configurations by ones from Policies
        $WAUPolicies.PSObject.Properties | ForEach-Object {
            $WAUConfig.PSObject.Properties.add($_)
        }

    }

    #Return config
    return $WAUConfig
}
