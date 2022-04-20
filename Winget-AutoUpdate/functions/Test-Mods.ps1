#Function to check if modification exists in 'mods' directory

function Test-Mods ($app){

    if (Test-Path "$WorkingDir\mods\$app-install.ps1"){
        $ModsInstall = "$WorkingDir\mods\$app-install.ps1"
        $ModsUpgrade = "$WorkingDir\mods\$app-install.ps1"
    }
    if (Test-Path "$WorkingDir\mods\$app-upgrade.ps1"){
        $ModsUpgrade = "$WorkingDir\mods\$app-upgrade.ps1"
    }
    else{
        return 0
    }

    return $ModsInstall,$ModsUpgrade
    
}