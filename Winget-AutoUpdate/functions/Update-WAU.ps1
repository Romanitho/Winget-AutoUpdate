
function Update-WAU ($VersionToUpdate){
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
        Write-Log "Starting downloading the GitHub Repository version $VersionToUpdate"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/archive/refs/tags/v$($VersionToUpdate).zip/" -OutFile $ZipFile
        Write-Log "Download finished" "Green"

        #Extract Zip File
        Write-Log "Starting unzipping the WAU GitHub Repository"
        $location = "$WorkingDir\WAU_update"
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Get-ChildItem -Path $location -Recurse | Unblock-File
        Write-Log "Unzip finished" "Green"
        $TempPath = (Resolve-Path "$location\*\Winget-AutoUpdate\").Path
        Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Exclude "icons" -Recurse -Force
        
        #Remove update zip file
        Write-Log "Cleaning temp files"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        #Remove update folder
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to about.xml
        [xml]$XMLconf = Get-content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
        $XMLconf.app.version = $VersionToUpdate
        $XMLconf.Save("$WorkingDir\config\about.xml")

        #Send success Notif
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $LatestVersion
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
        Write-Log "WAU Update failed"
    }
}
