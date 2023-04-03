#Function to check if modification exists within 'mods' directory

function Test-Mods ($app) {

    #Takes care of a null situation
    $ModsPreInstall = $null
    $ModsOverride = $null
    $ModsUpgrade = $null
    $ModsInstall = $null
    $ModsInstalled = $null

    $Mods = "$WorkingDir\mods"
    if (Test-Path "$Mods\$app-*") {
        if (Test-Path "$Mods\$app-preinstall.ps1") {
            $ModsPreInstall = "$Mods\$app-preinstall.ps1"
        }
        if (Test-Path "$Mods\$app-override.txt") {
            $ModsOverride = Get-Content "$Mods\$app-override.txt" -Raw
        }
        if (Test-Path "$Mods\$app-install.ps1") {
            $ModsInstall = "$Mods\$app-install.ps1"
            $ModsUpgrade = "$Mods\$app-install.ps1"
        }
        if (Test-Path "$Mods\$app-upgrade.ps1") {
            $ModsUpgrade = "$Mods\$app-upgrade.ps1"
        }
        if (Test-Path "$Mods\$app-installed.ps1") {
            $ModsInstalled = "$Mods\$app-installed.ps1"
        }
    }

    return $ModsPreInstall, $ModsOverride, $ModsUpgrade, $ModsInstall, $ModsInstalled

}
