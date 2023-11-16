#Function to check the connectivity
# rewritten to use INetworkListManager interface
# https://learn.microsoft.com/en-us/windows/win32/api/netlistmgr/nn-netlistmgr-inetworklistmanager?redirectedfrom=MSDN#methods

function Test-Network {
    Write-ToLog "Checking internet connection..." "Yellow"
    $NetworkListManager = [Activator]::CreateInstance([Type]::GetTypeFromCLSID(‘DCB00C01-570F-4A9B-8D69-199FDBA5723B’));
    if($NetworkListManager.IsConnectedToInternet)
    {
        Write-ToLog "Connected!" "Green";

        #Check for metered connection
        [void][Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
        $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()
        if ($cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or ($cost.NetworkCostType -ne "Unrestricted")) 
        {
            Write-ToLog "Metered connection detected." "Yellow"
            $DoNotRunOnMetered = $WAUConfig.WAU_DoNotRunOnMetered -eq 1;
            if ($DoNotRunOnMetered) 
            {
                Write-ToLog "WAU is configured to bypass update checking on metered connection" "Yellow"
            }
            else 
            {
                Write-ToLog "WAU is configured to force update checking on metered connection" "Yellow"
            }
            return !$DoNotRunOnMetered;
        }
        else 
        {
            return $true
        }
    }
    else
    {
        #Send Timeout Notif if no connection
        Write-ToLog "No internet connection!" "Red"

        #Notification for user shall be sent via scheduled task with popup
        $Title = $Script:NotifLocale.local.outputs.output[1].title
        $Message = $Script:NotifLocale.local.outputs.output[1].message
        $MessageType = "error"
        $Balise = "Connection"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise;
    }
    return $NetworkListManager.IsConnectedToInternet;
}
