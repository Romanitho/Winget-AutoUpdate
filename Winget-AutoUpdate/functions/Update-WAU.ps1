#Function to update WAU

function Update-WAU {

    $OnClickAction = "https://github.com/Romanitho/Winget-AutoUpdate/releases"
    $Button1Text = $NotifLocale.local.outputs.output[10].message

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

    #Run WAU update
    try {

        #Force to create a zip file
        $ZipFile = "$WorkingDir\WAU_update.zip"
        New-Item $ZipFile -ItemType File -Force | Out-Null

        #Download the zip
        Write-ToLog "Downloading the GitHub Repository version $WAUAvailableVersion" "Cyan"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$($WAUAvailableVersion)/WAU.zip" -OutFile $ZipFile

        #Extract Zip File
        Write-ToLog "Unzipping the WAU Update package" "Cyan"
        $location = "$WorkingDir\WAU_update"
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Get-ChildItem -Path $location -Recurse | Unblock-File

        #Update scritps
        Write-ToLog "Updating WAU..." "Yellow"
        $TempPath = (Resolve-Path "$location\Winget-AutoUpdate\")[0].Path
        if ($TempPath) {
            Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Exclude "icons" -Recurse -Force
        }

        #Remove update zip file and update temp folder
        Write-ToLog "Done. Cleaning temp files..." "Cyan"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to registry
        $WAUConfig | New-ItemProperty -Name DisplayVersion -Value $WAUAvailableVersion -Force
        $WAUConfig | New-ItemProperty -Name VersionMajor -Value ([version]$WAUAvailableVersion.Replace("-", ".")).Major -Force
        $WAUConfig | New-ItemProperty -Name VersionMinor -Value ([version]$WAUAvailableVersion.Replace("-", ".")).Minor -Force

        #Set Post Update actions to 1
        $WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 1 -Force

        #Send success Notif
        Write-ToLog "WAU Update completed." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

        #Rerun with newer version
        Write-ToLog "Re-run WAU"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade.ps1`""

        exit

    }

    catch {

        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
        Write-ToLog "WAU Update failed" "Red"

    }

}