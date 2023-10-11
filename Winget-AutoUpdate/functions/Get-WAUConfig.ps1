#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Get WAU Configurations
    $WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #Get WAU Policies
    $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #If WAU Policies detected, apply settings
    if ($($WAUPolicies.WAU_ActivateGPOManagement -eq 1)) {

        #Replace loaded configurations by ones from Policies
        $WAUPolicies.PSObject.Properties | ForEach-Object {
            $WAUConfig.PSObject.Properties.add($_)
        }

        #Add tag to activate WAU-Policies scheduled task
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name WAU_RunGPOManagement -Value 1 -Force | Out-Null
    }

    return $WAUConfig
}