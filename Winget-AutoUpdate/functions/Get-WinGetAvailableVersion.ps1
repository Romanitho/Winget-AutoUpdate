#Function to get the latest WinGet available version on Github
Function Get-WinGetAvailableVersion {

    #Get latest WinGet info
    $WinGeturl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'

    try {
        #Return latest version
        return ((Invoke-WebRequest $WinGeturl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
    }
    catch {
        #if fail set version to the latest version as of 2023-10-08
        return "1.6.2771"
    }

}
