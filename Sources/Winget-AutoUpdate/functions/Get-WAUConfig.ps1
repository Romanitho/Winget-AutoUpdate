#Function to get the WAU settings, including Domain/Local Policies (GPO)

Function Get-WAUConfig {

    #Get WAU Configurations from install config
    $WAUConfig_64_86 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate*", "HKLM:\SOFTWARE\WOW6432Node\Romanitho\Winget-AutoUpdate*" -ErrorAction SilentlyContinue | Sort-Object { $_.ProductVersion } -Descending
    $WAUConfig = $WAUConfig_64_86[0]

    #Check if GPO policies exist
    $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue

    #If GPO policies exist, apply them (regardless of ActivateGPOManagement value)
    if ($WAUPolicies) {
        Write-ToLog "GPO policies detected - applying GPO configuration" "Yellow"

        #Replace loaded configurations by ones from Policies
        $WAUPolicies.PSObject.Properties | ForEach-Object {
            $WAUConfig.PSObject.Properties.add($_)
        }
    }

    #Return config
    return $WAUConfig
}
