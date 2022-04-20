#Function to check if modification exists in 'mods' directory

function Test-Mods ($app){

    #Takes care of a null situation
    $ModsInstall = ""
    $ModsUpgrade = ""

    $Mods = "$WorkingDir\mods"
    if (Test-Path "$Mods\$app-*"){
        if (Test-Path "$Mods\$app-install.ps1"){
            $ModsInstall = "$Mods\$app-install.ps1"
            $ModsUpgrade = "$Mods\$app-install.ps1"
        }
        if (Test-Path "$Mods\$app-upgrade.ps1"){
            $ModsUpgrade = "$Mods\$app-upgrade.ps1"
        }
        return $ModsInstall,$ModsUpgrade
    }
    else {
        return 0
    }

}
