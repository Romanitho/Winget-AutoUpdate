<#
.SYNOPSIS
    Tests internet connectivity and metered connection status.

.DESCRIPTION
    Verifies network using NCSI probes with 30-minute timeout.
    Respects WAU_DoNotRunOnMetered setting.

.OUTPUTS
    Boolean: True if connected and allowed to proceed.
#>
function Test-Network {

    Write-ToLog "Checking internet connection..." "Yellow"

    # Get NCSI settings
    try {
        $NlaRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
        $ncsiHost = Get-ItemPropertyValue $NlaRegKey -Name ActiveWebProbeHost
        $ncsiPath = Get-ItemPropertyValue $NlaRegKey -Name ActiveWebProbePath
        $ncsiContent = Get-ItemPropertyValue $NlaRegKey -Name ActiveWebProbeContent
    }
    catch {
        $ncsiHost = "www.msftconnecttest.com"
        $ncsiPath = "connecttest.txt"
        $ncsiContent = "Microsoft Connect Test"
    }

    # Test connectivity (30 min timeout)
    for ($timeout = 0; $timeout -lt 1800; $timeout += 10) {
        try {
            $response = Invoke-WebRequest -Uri "http://${ncsiHost}/${ncsiPath}" -UseBasicParsing -UserAgent ([Microsoft.PowerShell.Commands.PSUserAgent]::Chrome) # DevSkim: ignore DS137138
        }
        catch { $response = $null }

        if ($response -and $response.StatusCode -eq 200 -and $response.Content -eq $ncsiContent) {
            Write-ToLog "Connected!" "Green"

            # Check metered connection
            try {
                [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
                $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()
                $networkCostTypeName = [Windows.Networking.Connectivity.NetworkCostType]::GetName([Windows.Networking.Connectivity.NetworkCostType], $cost.NetworkCostType)
            }
            catch {
                Write-ToLog "Could not check metered status - continuing" "Gray"
                return $true
            }

            $isMetered = $cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or $networkCostTypeName -ne "Unrestricted"

            if ($isMetered) {
                Write-ToLog "Metered connection detected." "Yellow"
                if ($WAUConfig.WAU_DoNotRunOnMetered -eq 1) {
                    Write-ToLog "WAU configured to skip on metered connection"
                    return $false
                }
                Write-ToLog "WAU configured to continue on metered connection"
            }
            return $true
        }

        Start-Sleep 10

        # Notify after 5 minutes
        if ($timeout -eq 300) {
            Write-ToLog "No connection notification sent." "Yellow"
            Start-NotifTask -Title $NotifLocale.local.outputs.output[0].title `
                -Message $NotifLocale.local.outputs.output[0].message -MessageType "warning" -Balise "Connection"
        }
    }

    # Timeout
    Write-ToLog "Timeout - No internet connection!" "Red"
    Start-NotifTask -Title $NotifLocale.local.outputs.output[1].title `
        -Message $NotifLocale.local.outputs.output[1].message -MessageType "error" -Balise "Connection"
    return $false
}