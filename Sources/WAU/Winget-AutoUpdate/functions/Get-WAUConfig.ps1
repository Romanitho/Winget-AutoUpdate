#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Get WAU Configurations from install config
    $WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

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