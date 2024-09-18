#Function to get the latest WAU available version on Github

function Get-WAUAvailableVersion {

    #Get Github latest version
    if ($WAUConfig.WAU_UpdatePrerelease -eq 1) {

        #Log
        Write-ToLog "WAU AutoUpdate Pre-release versions is Enabled" "Cyan"

        try {
            #Get latest pre-release info
            $WAUurl = "https://api.github.com/repos/Romanitho/$($GitHub_Repo)/releases"
            $WAUAvailableVersion = ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
        }
        catch {
            $url = "https://github.com/Romanitho/$($GitHub_Repo)/releases"
            $link = ((Invoke-WebRequest $url -UseBasicParsing).Links.href -match "/$($GitHub_Repo)/releases/tag/v*")[0]
            $WAUAvailableVersion = $link.Trim().Split("v")[-1]
        }

    }
    else {

        try {
            #Get latest stable info
            $WAUurl = "https://api.github.com/repos/Romanitho/$($GitHub_Repo)/releases/latest"
            $WAUAvailableVersion = ((Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
        }
        catch {
            $url = "https://github.com/Romanitho/$($GitHub_Repo)/releases/latest"
            $link = ((Invoke-WebRequest $url -UseBasicParsing).Links.href -match "/$($GitHub_Repo)/releases/tag/v*")[0]
            $WAUAvailableVersion = $link.Trim().Split("v")[-1]
        }

    }

    #Return version
    return $WAUAvailableVersion

}
