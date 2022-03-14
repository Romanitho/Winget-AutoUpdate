function Start-WAUUpdateCheck{
    #Get AutoUpdate status
    [xml]$UpdateStatus = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    $AutoUpdateStatus = $UpdateStatus.app.WAUautoupdate
    
    #Get current installed version
    [xml]$About = Get-Content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    [version]$Script:CurrentVersion = $About.app.version
    
    #Check if AutoUpdate is enabled
    if ($AutoUpdateStatus -eq $false){
        Write-Log "WAU Current version: $CurrentVersion. AutoUpdate is disabled." "Cyan"
        return $false
    }
    #If enabled, check online available version
    else{
        #Get Github latest version
        $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases/latest'
        $LatestVersion = (Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name
        [version]$AvailableVersion = $LatestVersion.Replace("v","")

        #If newer version is avalable, return $True
        if ($AvailableVersion -gt $CurrentVersion){
            Write-Log "WAU Current version: $CurrentVersion. Version $AvailableVersion is available." "Yellow"
            return $true
        }
        else{
            Write-Log "WAU Current version: $CurrentVersion. Up to date." "Green"
            return $false
        }
    }
}
