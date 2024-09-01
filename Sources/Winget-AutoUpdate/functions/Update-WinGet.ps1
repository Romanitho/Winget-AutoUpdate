#Function to download and update WinGet

Function Update-WinGet {

    Write-ToLog "Checking if WinGet is installed/up to date." "Yellow"

    #Get latest WinGet info
    $WinGeturl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'

    try {
        #Return latest version
        $WinGetAvailableVersion = ((Invoke-WebRequest $WinGeturl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
    }
    catch {
        #if fail set version to the latest version as of 2024-04-29
        $WinGetAvailableVersion = "1.7.11132"
    }

    try {
        #Get Admin Context Winget Location
        $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        #If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo[-1].FileName
        #Get current Winget Version
        $WingetInstalledVersion = [regex]::match((& $WingetCmd -v), '((\d+\.)(\d+\.)(\d+))').Groups[1].Value
    }
    catch {
        Write-ToLog "-> WinGet is not installed" "Red"
    }

    #Check if the current available WinGet is newer than the installed
    if ($WinGetAvailableVersion -gt $WinGetInstalledVersion) {

        #Install WinGet MSIXBundle in SYSTEM context
        try {
            #Download WinGet MSIXBundle
            Write-ToLog "-> Downloading WinGet MSIXBundle for App Installer..."
            $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            $WingetInstaller = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            Invoke-RestMethod -Uri $WinGetURL -OutFile $WingetInstaller

            #Install
            Write-ToLog "-> Installing WinGet MSIXBundle for App Installer..."
            Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
            Write-ToLog "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully!" "green"

            #Reset WinGet Sources
            $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
            #If multiple versions, pick most recent one
            $WingetCmd = $WingetInfo[-1].FileName
            & $WingetCmd source reset --force
            Write-ToLog "-> WinGet sources reset.`n" "green"
            $return = "success"

        }
        catch {
            Write-ToLog "-> Failed to install WinGet MSIXBundle for App Installer...`n" "red"
            #Force Store Apps to update
            Update-StoreApps
            $return = "fail"
        }

        #Remove WinGet MSIXBundle
        Remove-Item -Path $WingetInstaller -Force -ErrorAction SilentlyContinue

        #Return status
        return $return
    }
    else {
        Write-ToLog "-> WinGet is up to date: v$WinGetInstalledVersion`n" "Green"
        return "current"
    }
}
