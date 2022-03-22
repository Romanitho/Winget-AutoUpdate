function Test-Network {
    #Init
    $timeout = 0

    #Test connectivity during 30 min then timeout
    Write-Log "Checking internet connection..." "Yellow"
    While ($timeout -lt 1800){
        $TestNetwork = Test-NetConnection 8.8.8.8 -Port 443 -InformationLevel Quiet  
        if ($TestNetwork){
            Write-Log "Connected !" "Green"
            return $true
        }
        else{
            Start-Sleep 10
            $timeout += 10
            
            #Send Warning Notif if no connection for 5 min
            if ($timeout -eq 300){
                Write-Log "Notify 'No connection' sent." "Yellow"
                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "connection"
                Start-NotifTask $Title $Message $MessageType $Balise
            }
        }
    }
    
    #Send Timeout Notif if no connection for 30 min
    Write-Log "Timeout. No internet connection !" "Red"
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "connection"
    Start-NotifTask $Title $Message $MessageType $Balise
    return $false
}