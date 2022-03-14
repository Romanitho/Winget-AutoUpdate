
function Update-WAU{
    #Get WAU Github latest version
    $WAUurl = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases/latest'
    $LatestVersion = (Invoke-WebRequest $WAUurl -UseBasicParsing | ConvertFrom-Json)[0].tag_name

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $CurrentVersion, $LatestVersion.Replace("v","")
    $MessageType = "info"
    $Balise = "Winget-AutoUpdate"
    Start-NotifTask $Title $Message $MessageType $Balise

    #Run WAU update
    try{
        #Force to create a zip file 
        $ZipFile = "$WorkingDir\WAU_update.zip"
        New-Item $ZipFile -ItemType File -Force | Out-Null

        #Download the zip 
        Write-Log "Starting downloading the GitHub Repository"
        Invoke-RestMethod -Uri "https://api.github.com/repos/Romanitho/Winget-AutoUpdate/zipball/$($LatestVersion)" -OutFile $ZipFile
        Write-Log 'Download finished'

        #Extract Zip File
        Write-Log "Starting unzipping the WAU GitHub Repository"
        $location = "$WorkingDir\WAU_update"
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Get-ChildItem -Path $location -Recurse | Unblock-File
        Write-Log "Unzip finished"
        $TempPath = (Resolve-Path "$location\Romanitho-Winget-AutoUpdate*\Winget-AutoUpdate\").Path
        Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Recurse -Force
        
        #Remove update zip file
        Write-Log "Cleaning temp files"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        #Remove update folder
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to conf.xml
        [xml]$XMLconf = Get-content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
        $XMLconf.app.version = $LatestVersion.Replace("v","")
        $XMLconf.Save("$WorkingDir\config\about.xml")

        #Send success Notif
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $LatestVersion
        $MessageType = "success"
        $Balise = "Winget-AutoUpdate"
        Start-NotifTask $Title $Message $MessageType $Balise

        #Rerun with newer version
	    Write-Log "Re-run WAU"
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade`""
        exit
    }
    catch{
        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        $Balise = "Winget-AutoUpdate"
        Start-NotifTask $Title $Message $MessageType $Balise
        Write-Log "WAU Update failed"
    }
}