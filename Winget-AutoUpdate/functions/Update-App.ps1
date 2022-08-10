#Function to Update an App

Function Update-App ($app) {

    #Get App Info
    $OnClickAction = Get-AppInfo $app.Id

    #Send available update notification
    Write-Log "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
    $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
    $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
    $MessageType = "info"
    $Balise = $($app.Name)
    Start-NotifTask $Title $Message $MessageType $Balise $OnClickAction

    #Winget upgrade
    Write-Log "##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"
    
    #Run Winget Upgrade command
    & $Winget upgrade --id $($app.Id) --all --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append

    #Set mods to apply as an upgrade
    $ModsMode = "Upgrade"

    #Check if application updated properly
    $CheckOutdated = Get-WingetOutdatedApps
    $FailedToUpgrade = $false
    foreach ($CheckApp in $CheckOutdated) {
        if ($($CheckApp.Id) -eq $($app.Id)) {
            
            #Upgrade failed!
            #Test for a Pending Reboot (Component Based Servicing/WindowsUpdate/CCM_ClientUtilities)
            $PendingReboot = Test-PendingReboot
            if ($PendingReboot -eq $true) {
                Write-Log "A Pending Reboot lingers and probably prohibited $($app.Name) from upgrading...`n...an install for $($app.Name) is NOT executed!" "Red"
                $FailedToUpgrade = $true
                break
            }
    
            #If app failed to upgrade, run Install command
            Write-Log "An upgrade for $($app.Name) failed, now trying an install..." "Yellow"
            & $Winget install --id $($app.Id) --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append

            #Set mods to apply as an install
            $ModsMode = "Install"

            #Check if application installed properly
            $CheckOutdated2 = Get-WingetOutdatedApps
            foreach ($CheckApp2 in $CheckOutdated2) {
                if ($($CheckApp2.Id) -eq $($app.Id)) {
                    $FailedToUpgrade = $true
                }
            }
        }
    }

    if ($FailedToUpgrade -eq $false) {

        #Check if mods exist for install/upgrade
        $ModsInstall, $ModsUpgrade = Test-Mods $($app.Id)

        if (($ModsUpgrade) -and ($ModsMode -eq "Upgrade")) {
            Write-Log "Modifications for $($app.Id) after upgrade are being applied..." "Yellow"
            & "$ModsUpgrade"
        }
        elseif (($ModsInstall) -and ($ModsMode -eq "Install")) {
            Write-Log "Modifications for $($app.Id) after install are being applied..." "Yellow"
            & "$ModsInstall"
        }
    }

    Write-Log "##########   WINGET UPGRADE PROCESS FINISHED FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"   

    #Notify installation
    if ($FailedToUpgrade -eq $false) {   

        #Send success updated app notification
        Write-Log "$($app.Name) updated to $($app.AvailableVersion) !" "Green"
        
        #Send Notif
        $Title = $NotifLocale.local.outputs.output[3].title -f $($app.Name)
        $Message = $NotifLocale.local.outputs.output[3].message -f $($app.AvailableVersion)
        $MessageType = "success"
        $Balise = $($app.Name)
        Start-NotifTask $Title $Message $MessageType $Balise $OnClickAction

        $Script:InstallOK += 1
        
    }
    else {

        #Send failed updated app notification
        Write-Log "$($app.Name) update failed." "Red"
        
        #Send Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f $($app.Name)
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        $Balise = $($app.Name)
        Start-NotifTask $Title $Message $MessageType $Balise $OnClickAction
    
    }

}