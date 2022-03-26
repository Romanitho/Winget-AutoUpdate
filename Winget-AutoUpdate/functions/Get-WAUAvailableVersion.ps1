function Get-WAUAvailableVersion {
    #Get Github latest version
    if ($true -eq $WAUprerelease) {
        #Get latest pre-release info
        $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases'
    }
    else {
        #Get latest stable info
        $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases/latest'
    }
    $Script:WAUAvailableVersion = ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v","")
}