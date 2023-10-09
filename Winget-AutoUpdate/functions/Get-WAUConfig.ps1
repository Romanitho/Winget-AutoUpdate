#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Get WAU Configurations
    $WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #Get WAU Policies
    $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #If WAU Policies detected, apply settings
    if ($($WAUPolicies.WAU_ActivateGPOManagement -eq 1)) {

        Write-ToLog "WAU Policies management activated."

        #Replace loaded configurations by ones from Policies in 'WAUConfig'
        $WAUPolicies.PSObject.Properties | ForEach-Object {
            $WAUConfig.PSObject.Properties.add($_)
        }

        #Add tag to activate WAU-Policies
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name WAU_ManagementTag -Value 1 -Force | Out-Null
    }

    return $WAUConfig
}