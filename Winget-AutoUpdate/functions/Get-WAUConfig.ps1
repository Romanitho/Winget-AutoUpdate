#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Check if GPO Management is enabled
    $ActivateGPOManagement = Get-ItemPropertyValue "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -Name "WAU_ActivateGPOManagement" -ErrorAction SilentlyContinue

    if ($ActivateGPOManagement -eq 1) {

        #Add a tag to activate WAU-Policies scheduled task
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name WAU_RunGPOManagement -Value 1 -Force | Out-Null

        #Get all WAU Policies
        $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue
    }

    #Get WAU Configurations from install config
    $WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #If GPO Management is enabled, replace settings
    if ($ActivateGPOManagement -eq 1) {

        #Replace loaded configurations by ones from Policies
        $WAUPolicies.PSObject.Properties | ForEach-Object {
            $WAUConfig.PSObject.Properties.add($_)
        }
    }

    #Return config
    return $WAUConfig
}