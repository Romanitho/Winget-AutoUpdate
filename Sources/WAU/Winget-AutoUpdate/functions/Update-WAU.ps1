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
        $ServiceUI = Test-Path "$WorkingDir\ServiceUI.exe"
        if ($TempPath -and $ServiceUI) {
            #Do not copy ServiceUI if already existing, causing error if in use.
            Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Exclude ("icons", "ServiceUI.exe") -Recurse -Force
        }
        elseif ($TempPath) {
            Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Exclude "icons" -Recurse -Force
        }

        #Remove update zip file and update temp folder
        Write-ToLog "Done. Cleaning temp files..." "Cyan"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to registry
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name "DisplayVersion" -Value $WAUAvailableVersion -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "ProductVersion" -Value $WAUAvailableVersion -Force | Out-Null

        #Set Post Update actions to 1
        New-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate" -Name "WAU_PostUpdateActions" -Value 1 -Force | Out-Null

        #Send success Notif
        Write-ToLog "WAU Update completed." "Green"
        $Title = $NotifLocale.local.outputs.output[3].title -f "Winget-AutoUpdate"
        $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
        $MessageType = "success"
        Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

        #Rerun with newer version
        Write-ToLog "Re-run WAU"
        Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade.ps1`""

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