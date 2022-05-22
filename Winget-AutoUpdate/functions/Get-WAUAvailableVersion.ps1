#Function to get latest WAU available version on Github

function Get-WAUAvailableVersion {

    #Get Github latest version
    if ($WAUConfig.WAU_UpdatePrerelease -eq 1) {
        
        #Get latest pre-release info
        $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases'
    
    }
    else {
        
        #Get latest stable info
        $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases/latest'
    
    }

    return ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v","")

}