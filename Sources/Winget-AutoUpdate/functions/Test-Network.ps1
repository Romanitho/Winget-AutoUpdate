function Test-Network {
    param (
        [int]$TimeoutInSeconds = 1800,
        [int]$RetryIntervalInSeconds = 10
    )

    # Init
    $timeout = 0
    Write-ToLog "Checking internet connection..." "Yellow"

    # Retrieve NCSI values
    try {
        $NlaRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
        $ncsiHost = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbeHost
        $ncsiPath = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbePath
        $ncsiContent = Get-ItemPropertyValue -Path $NlaRegKey -Name ActiveWebProbeContent
    } catch {
        Write-ToLog "Error reading NCSI registry keys: $($_.Exception.Message)" "Red"
        $ncsiHost = "www.msftconnecttest.com"
        $ncsiPath = "connecttest.txt"
        $ncsiContent = "Microsoft Connect Test"
    }

    while ($timeout -lt $TimeoutInSeconds) {
        try {
            $ncsiResponse = Invoke-WebRequest -Uri "http://$($ncsiHost)/$($ncsiPath)" -UseBasicParsing
        } catch {
            Write-ToLog "Error during web request: $($_.Exception.Message)" "Red"
            $ncsiResponse = $false
        }

        if ($ncsiResponse -and $ncsiResponse.StatusCode -eq 200 -and $ncsiResponse.Content -eq $ncsiContent) {
            Write-ToLog "Connected!" "Green"

            # Check for metered connection
            [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
            $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()

            if ($cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or ($cost.NetworkCostType -ne "Unrestricted")) {
                Write-ToLog "Metered connection detected." "Yellow"
                
                return ($WAUConfig.WAU_DoNotRunOnMetered -ne 1)
            }

            return $true
        } else {
            Start-Sleep -Seconds $RetryIntervalInSeconds
            $timeout += $RetryIntervalInSeconds

            # Send Warning Notif if no connection for 5 min
            if ($timeout -eq 300) {
                # Log
                Write-ToLog "Notify 'No connection' sent." "Yellow"

                # Notif
                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "Connection"
                Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise
            }
        }
    }

    # Send Timeout Notif if no connection for 30 min
    Write-ToLog "Timeout. No internet connection!" "Red"

    # Notif
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "Connection"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise

    return $false
}