#Function to update WAU

function Update-WAU {

    $OnClickAction = "https://github.com/Romanitho/$($GitHub_Repo)/releases"
    $Button1Text = $NotifLocale.local.outputs.output[10].message

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "Winget-AutoUpdate"
    $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
    $MessageType = "info"
    Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text

    #Run WAU update

    #Try WAU.msi (v2) if available
    try {
        #Download the msi
        Write-ToLog "Downloading the GitHub Repository MSI version $WAUAvailableVersion" "Cyan"
        $MsiFile = "$env:temp\WAU.msi"
        Invoke-RestMethod -Uri "https://github.com/Romanitho/$($GitHub_Repo)/releases/download/v$($WAUAvailableVersion)/WAU.msi" -OutFile $MsiFile

        #Migrate registry to save current WAU settings
        Write-ToLog "Saving current config before updating with MSI"
        $sourcePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
        $destinationPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
        #Create the destination key if it doesn't exist
        if (-not (Test-Path -Path $destinationPath)) {
            New-Item -Path $destinationPath -ItemType Directory -Force
            Write-ToLog "New registry key created."
        }
        #Create missing default values
        Set-ItemProperty -Path $destinationPath -Name "WAU_DoNotRunOnMetered" -Value 0 -Type Dword
        Write-ToLog "WAU_DoNotRunOnMetered created. Value: 0"
        Set-ItemProperty -Path $destinationPath -Name "WAU_UpdatesAtLogon" -Value 0 -Type Dword
        Write-ToLog "WAU_UpdatesAtLogon created. Value 0"
        #Retrieve the properties of the source key
        $properties = Get-ItemProperty -Path $sourcePath
        foreach ($property in $properties.PSObject.Properties) {
            #Check if the value name starts with "WAU_"
            if ($property.Name -like "WAU_*" -and $property.Name -notlike "WAU_PostUpdateActions*") {
                #Copy the value to the destination key
                Set-ItemProperty -Path $destinationPath -Name $property.Name -Value $property.Value
                Write-ToLog "$($property.Name) saved. Value: $($property.Value)"
            }
        }

        #Stop ServiceUI
        $ServiceUI = Get-Process -ProcessName serviceui -ErrorAction SilentlyContinue
        if ($ServiceUI) {
            try {
                Write-ToLog "Stopping ServiceUI"
                $ServiceUI | Stop-Process
            }
            catch {
                Write-ToLog "Failed to stop ServiceUI"
            }
        }

        #Uninstall WAU v1
        Write-ToLog "Uninstalling WAU v1"
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\WAU-Uninstall.ps1`" -NoClean" -Wait

        #Update WAU and run
        Write-ToLog "Updating WAU..." "Yellow"
        Start-Process msiexec.exe -ArgumentList "/i $MsiFile /qn /L*v ""$WorkingDir\logs\WAU-Installer.log"" RUN_WAU=YES INSTALLDIR=""$WorkingDir"""

        Exit 0
    }

    catch {

        try {
            #Try WAU.zip (v1)

            Write-ToLog "No MSI found yet."

            #Force to create a zip file
            $ZipFile = "$WorkingDir\WAU_update.zip"
            New-Item $ZipFile -ItemType File -Force | Out-Null

            #Download the zip
            Write-ToLog "Downloading the GitHub Repository Zip version $WAUAvailableVersion" "Cyan"
            Invoke-RestMethod -Uri "https://github.com/Romanitho/$($GitHub_Repo)/releases/download/v$($WAUAvailableVersion)/WAU.zip" -OutFile $ZipFile

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

            #Get installed version
            $InstalledVersion = Get-Content "$TempPath\Version.txt"

            #Remove update zip file and update temp folder
            Write-ToLog "Done. Cleaning temp files..." "Cyan"
            Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

            #Set new version to registry
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name "DisplayVersion" -Value $InstalledVersion -Force | Out-Null

            #Set Post Update actions to 1
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name "WAU_PostUpdateActions" -Value 1 -Force | Out-Null

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

            Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue

        }
    }

}
