#Write to Log Function

function Write-ToLog ($LogMsg, $LogColor = "White") {

    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"

    #Echo log
    $Log | Write-host -ForegroundColor $LogColor

    #Write log to file
    $Log | Out-File -FilePath $LogFile -Append

}
