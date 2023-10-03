#Get the winget App Information

Function Get-AppInfo ($AppID) {
    #Get AppID Info
    $String = & $winget show $AppID --accept-source-agreements -s winget | Out-String

    #Search for Release Note info
    $ReleaseNote = [regex]::match($String, "(?<=Release Notes Url: )(.*)(?=\n)").Groups[0].Value

    #Return Release Note
    return $ReleaseNote
}
