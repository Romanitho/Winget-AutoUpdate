#Function to check the connectivity

function Test-Network {

    # Init
    $timeout = 0

    #Test connectivity during 30 min then timeout
    Write-ToLog "Checking internet connection..." "Yellow"

    try {
        $NlaRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
        $ncsiHost = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbeHost
        $ncsiPath = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbePath
        $ncsiContent = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbeContent
    }
    catch {
        $ncsiHost = "www.msftconnecttest.com"
        $ncsiPath = "connecttest.txt"
        $ncsiContent = "Microsoft Connect Test"
    }

    while ($timeout -lt 1800) {
        try {
            $ncsiResponse = Invoke-WebRequest -Uri "http://$($ncsiHost)/$($ncsiPath)" -UseBasicParsing -UserAgent ([Microsoft.PowerShell.Commands.PSUserAgent]::Chrome); # DevSkim: ignore DS137138 Insecure URL
        }
        catch {
            $ncsiResponse = $false
        }

        if (($ncsiResponse) -and ($ncsiResponse.StatusCode -eq 200) -and ($ncsiResponse.content -eq $ncsiContent)) {
            Write-ToLog "Connected !" "Green"

            # Check for metered connection
            try {
                [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
                $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()

                $networkCostTypeName = [Windows.Networking.Connectivity.NetworkCostType]::GetName(
                    [Windows.Networking.Connectivity.NetworkCostType],
                    $cost.NetworkCostType
                )
            }
            catch {
                Write-ToLog "Could not evaluate metered connection status - skipping check." "Gray"
                return $true
            }

            if ($cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or ($networkCostTypeName -ne "Unrestricted")) {
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

            if ($timeout -eq 300) {
                Write-ToLog "Notify 'No connection' sent." "Yellow"

                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "Connection"
                Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise
            }
        }
    }

    Write-ToLog "Timeout. No internet connection !" "Red"

    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "Connection"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise

    return $false
}