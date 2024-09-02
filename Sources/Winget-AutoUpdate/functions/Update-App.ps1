#Function to update an App

Function Update-App ($app) {

    #Get App Info
    $ReleaseNoteURL = Get-AppInfo $app.Id
    if ($ReleaseNoteURL) {
        $Button1Text = $NotifLocale.local.outputs.output[10].message
    }

    #Send available update notification
    Write-ToLog "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
    $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
    $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
    $MessageType = "info"
    $Balise = $($app.Name)
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

    #Check if mods exist for preinstall/override/upgrade/install/installed/notinstalled
    $ModsPreInstall, $ModsOverride, $ModsUpgrade, $ModsInstall, $ModsInstalled, $ModsNotInstalled = Test-Mods $($app.Id)

    #Winget upgrade
    Write-ToLog "##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"

    #If PreInstall script exist
    if ($ModsPreInstall) {
        Write-ToLog "Modifications for $($app.Id) before upgrade are being applied..." "Yellow"
        & "$ModsPreInstall"
    }

    #Run Winget Upgrade command
    if ($ModsOverride) {
        Write-ToLog "-> Running (overriding default): Winget upgrade --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget --override $ModsOverride"
        & $Winget upgrade --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget --override $ModsOverride | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append
    }
    else {
        Write-ToLog "-> Running: Winget upgrade --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget -h"
        & $Winget upgrade --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget -h | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append
    }

    if ($ModsUpgrade) {
        Write-ToLog "Modifications for $($app.Id) during upgrade are being applied..." "Yellow"
        & "$ModsUpgrade"
    }

    #Check if application updated properly
    $ConfirmInstall = Confirm-Installation $($app.Id) $($app.AvailableVersion)

    if ($ConfirmInstall -ne $true) {
        #Upgrade failed!
        #Test for a Pending Reboot (Component Based Servicing/WindowsUpdate/CCM_ClientUtilities)
        $PendingReboot = Test-PendingReboot
        if ($PendingReboot -eq $true) {
            Write-ToLog "-> A Pending Reboot lingers and probably prohibited $($app.Name) from upgrading...`n-> ...an install for $($app.Name) is NOT executed!" "Red"
            break
        }

        #If app failed to upgrade, run Install command (2 tries max - some apps get uninstalled after single "Install" command.)
        $retry = 1
        While (($ConfirmInstall -eq $false) -and ($retry -le 2)) {

            Write-ToLog "-> An upgrade for $($app.Name) failed, now trying an install instead... ($retry/2)" "Yellow"

            if ($ModsOverride) {
                Write-ToLog "-> Running (overriding default): Winget install --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget --force --override $ModsOverride"
                & $Winget install --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget --force --override $ModsOverride | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append
            }
            else {
                Write-ToLog "-> Running: Winget install --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget -h --force"
                & $Winget install --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget -h --force | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append
            }

            if ($ModsInstall) {
                Write-ToLog "Modifications for $($app.Id) during install are being applied..." "Yellow"
                & "$ModsInstall"
            }

            #Check if application installed properly
            $ConfirmInstall = Confirm-Installation $($app.Id) $($app.AvailableVersion)
            $retry += 1
        }
    }

    switch ($ConfirmInstall) {
        # Upgrade/install was successful
        $true {
            if ($ModsInstalled) {
                Write-ToLog "Modifications for $($app.Id) after upgrade/install are being applied..." "Yellow"
                & "$ModsInstalled"
            }
        }
        # Upgrade/install was unsuccessful
        $false {
            if ($ModsNotInstalled) {
                Write-ToLog "Modifications for $($app.Id) after a failed upgrade/install are being applied..." "Yellow"
                & "$ModsNotInstalled"
            }
        }
    }

    Write-ToLog "##########   WINGET UPGRADE PROCESS FINISHED FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"

    #Notify installation
    if ($ConfirmInstall -eq $true) {

        #Send success updated app notification
        Write-ToLog "$($app.Name) updated to $($app.AvailableVersion) !" "Green"

        #Send Notif
        $Title = $NotifLocale.local.outputs.output[3].title -f $($app.Name)
        $Message = $NotifLocale.local.outputs.output[3].message -f $($app.AvailableVersion)
        $MessageType = "success"
        $Balise = $($app.Name)
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

        $Script:InstallOK += 1

    }
    else {

        #Send failed updated app notification
        Write-ToLog "$($app.Name) update failed." "Red"

        #Send Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f $($app.Name)
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        $Balise = $($app.Name)
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

    }

}
