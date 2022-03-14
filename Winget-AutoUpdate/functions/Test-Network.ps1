function Test-Network {
    #init
    $timeout = 0

    #test connectivity during 30 min then timeout
    Write-Log "Checking internet connection..." "Yellow"
    While ($timeout -lt 1800){
        try{
            Invoke-RestMethod -Uri "https://api.github.com/zen"
            Write-Log "Connected !" "Green"
            return $true
        }
        catch{
            Start-Sleep 10
            $timeout += 10
            Write-Log "Checking internet connection. $($timeout)s." "Yellow"
            #Send Notif if no connection for 5 min
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
    Write-Log "Timeout. No internet connection !" "Red"
    #Send Notif if no connection for 30 min
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "connection"
    Start-NotifTask $Title $Message $MessageType $Balise
    return $false
}