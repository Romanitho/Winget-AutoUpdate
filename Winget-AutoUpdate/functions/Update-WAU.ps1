
function Update-WAU {
    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    $Balise = "Winget-AutoUpdate"
    Start-NotifTask $Title $Message $MessageType $Balise

    #Run WAU update
    try{
        #Force to create a zip file 
        $ZipFile = "$WorkingDir\WAU_update.zip"
        New-Item $ZipFile -ItemType File -Force | Out-Null

        #Download the zip 
        Write-Log "Downloading the GitHub Repository version $WAUAvailableVersion" "Cyan"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/archive/refs/tags/v$($WAUAvailableVersion).zip/" -OutFile $ZipFile

        #Extract Zip File
        Write-Log "Unzipping the WAU GitHub Repository" "Cyan"
        $location = "$WorkingDir\WAU_update"
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Get-ChildItem -Path $location -Recurse | Unblock-File
        Write-Log "Updating WAU" "Yellow"
        $TempPath = (Resolve-Path "$location\*\Winget-AutoUpdate\")[0].Path
        if ($TempPath){
            Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Exclude "icons" -Recurse -Force
        }
        
        #Remove update zip file and update temp folder
        Write-Log "Done. Cleaning temp files" "Cyan"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to 'about.xml'
        [xml]$XMLconf = Get-content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
        $XMLconf.app.version = $WAUAvailableVersion
        $XMLconf.Save("$WorkingDir\config\about.xml")

        #Send success Notif
        Write-Log "WAU Update completed." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        $Balise = "Winget-AutoUpdate"
        Start-NotifTask $Title $Message $MessageType $Balise

        #Rerun with newer version
	    Write-Log "Re-run WAU"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade`""
        exit
    }
    catch{
        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        $Balise = "Winget-AutoUpdate"
        Start-NotifTask $Title $Message $MessageType $Balise
        Write-Log "WAU Update failed" "Red"
    }
}
