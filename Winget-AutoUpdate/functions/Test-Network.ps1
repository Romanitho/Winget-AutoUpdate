#Function to check the connectivity

function Test-Network {

    #Init
    $timeout = 0

    # Workaround for ARM64 (Access Denied / Win32 internal Server error)
    $ProgressPreference = 'SilentlyContinue'

    #Test connectivity during 30 min then timeout
    Write-ToLog "Checking internet connection..." "Yellow"
    While ($timeout -lt 1800) {

        $URLtoTest = "https://raw.githubusercontent.com/Romanitho/Winget-AutoUpdate/main/LICENSE"
        $URLcontent = ((Invoke-WebRequest -URI $URLtoTest -UseBasicParsing).content)

        if ($URLcontent -like "*MIT License*") {

            Write-ToLog "Connected !" "Green"

            #Check for metered connection
            [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
            $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()

            if ($cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or ($cost.NetworkCostType -ne "Unrestricted")) {

                Write-ToLog "Metered connection detected." "Yellow"

                if ($WAUConfig.WAU_DoNotRunOnMetered -eq 1) {

                    Write-ToLog "WAU is configured to bypass update checking on metered connection"
                    return $false

                }
                else {

                    Write-ToLog "WAU is configured to force update checking on metered connection"
                    return $true

                }

            }
            else {

                return $true

            }

        }
        else {

            Start-Sleep 10
            $timeout += 10

            #Send Warning Notif if no connection for 5 min
            if ($timeout -eq 300) {
                #Log
                Write-ToLog "Notify 'No connection' sent." "Yellow"

                #Notif
                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "Connection"
                Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise
            }

        }

    }

    #Send Timeout Notif if no connection for 30 min
    Write-ToLog "Timeout. No internet connection !" "Red"

    #Notif
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "Connection"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise

    return $false

}
