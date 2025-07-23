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
    $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsUpgrade, $ModsInstall, $ModsInstalled, $ModsNotInstalled = Test-Mods $($app.Id)

    #Winget upgrade
    Write-ToLog "##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"

    #If PreInstall script exist
    if ($ModsPreInstall) {
        Write-ToLog "Modifications for $($app.Id) before upgrade are being applied..." "DarkYellow"
        $preInstallResult = & "$ModsPreInstall"
        if ($preInstallResult -eq $false) {
            Write-ToLog "PreInstall script for $($app.Id) requested to skip this update" "Yellow"
            continue  # Skip to next app in the parent loop
        }
    }

	# Define upgrade base parameters
	$baseParams = @(
		"upgrade", 
		"--id", "$($app.Id)", 
		"-e", 
		"--accept-package-agreements", 
		"--accept-source-agreements", 
		"-s", "winget"
	)

	# Define base log message
	$baseLogMessage = "Winget upgrade --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget"

	# Determine which parameters and log message to use
	if ($ModsOverride) {
		$allParams = $baseParams + @("--override", "$ModsOverride")
		$logPrefix = "Running (overriding default):"
		$logSuffix = "--override $ModsOverride"
	} 
	elseif ($ModsCustom) {
		$allParams = $baseParams + @("-h", "--custom", "$ModsCustom")
		$logPrefix = "Running (customizing default):"
		$logSuffix = "-h --custom $ModsCustom"
	} 
	else {
		$allParams = $baseParams + @("-h")
		$logPrefix = "Running:"
		$logSuffix = "-h"
	}

	# Build the log message
	$logMessage = "$logPrefix $baseLogMessage $logSuffix"

	# Log the command
	Write-ToLog "-> $logMessage"

	# Execute command and log results
	& $Winget $allParams | Where-Object { $_ -notlike "   *" } | 
		Tee-Object -file $LogFile -Append

    if ($ModsUpgrade) {
        Write-ToLog "Modifications for $($app.Id) during upgrade are being applied..." "DarkYellow"
        & "$ModsUpgrade"
    }

    #Check if application updated properly
    $ConfirmInstall = Confirm-Installation $($app.Id) $($app.AvailableVersion)

    if ($ConfirmInstall -ne $true) {
        #Upgrade failed!
        #Test for a Pending Reboot (Component Based Servicing/WindowsUpdate/CCM_ClientUtilities)
        $PendingReboot = Test-PendingReboot
        if ($PendingReboot -eq $true) {
            Write-ToLog "-> A Pending Reboot lingers and probably prohibited $($app.Name) from upgrading...`n-> ...limiting to 1 install attempt instead of 2" "Yellow"
            $retry = 2
        }
        else {
            #If app failed to upgrade, run Install command (2 tries max - some apps get uninstalled after single "Install" command.)
            $retry = 1
        }
        
        While (($ConfirmInstall -eq $false) -and ($retry -le 2)) {

            Write-ToLog "-> An upgrade for $($app.Name) failed, now trying an install instead... ($retry/2)" "DarkYellow"

            # Define install base parameters
            $baseParams = @(
                "install", 
                "--id", "$($app.Id)", 
                "-e", 
                "--accept-package-agreements", 
                "--accept-source-agreements", 
                "-s", "winget",
                "--force"
            )

            # Define base log message
            $baseLogMessage = "Winget install --id $($app.Id) -e --accept-package-agreements --accept-source-agreements -s winget --force"

            # Determine which parameters and log message to use
            if ($ModsOverride) {
                $allParams = $baseParams + @("--override", "$ModsOverride")
                $logPrefix = "Running (overriding default):"
                $logSuffix = "--override $ModsOverride"
            } 
            elseif ($ModsCustom) {
                $allParams = $baseParams + @("-h", "--custom", "$ModsCustom")
                $logPrefix = "Running (customizing default):"
                $logSuffix = "-h --custom $ModsCustom"
            } 
            else {
                $allParams = $baseParams + @("-h")
                $logPrefix = "Running:"
                $logSuffix = "-h"
            }

            # Build the log message
            $logMessage = "$logPrefix $baseLogMessage $logSuffix"

            # Log the command
            Write-ToLog "-> $logMessage"

            # Execute command and log results
            & $Winget $allParams | Where-Object { $_ -notlike "   *" } | 
                Tee-Object -file $LogFile -Append

            if ($ModsInstall) {
                Write-ToLog "Modifications for $($app.Id) during install are being applied..." "DarkYellow"
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
                Write-ToLog "Modifications for $($app.Id) after upgrade/install are being applied..." "DarkYellow"
                & "$ModsInstalled"
            }
        }
        # Upgrade/install was unsuccessful
        $false {
            if ($ModsNotInstalled) {
                Write-ToLog "Modifications for $($app.Id) after a failed upgrade/install are being applied..." "DarkYellow"
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
