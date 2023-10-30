#Function to download and update WinGet

Function Update-WinGet ($WinGetAvailableVersion) {

    $download_string = "-> Downloading WinGet MSIXBundle for App Installer..."
    $install_string = "-> Installing WinGet MSIXBundle for App Installer..."
    $success_string = "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully!"
    $reset_string = "-> WinGet sources reset.`n"
    $fail_string = "-> Failed to install WinGet MSIXBundle for App Installer...`n"

    #Download WinGet MSIXBundle
    Write-ToLog $download_string
    $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WingetInstaller = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    Invoke-RestMethod -Uri $WinGetURL -OutFile $WingetInstaller

    #Install WinGet MSIXBundle in SYSTEM context
    try {
        Write-ToLog $install_string
        Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
        Write-ToLog $success_string "green"

        #Reset WinGet Sources
        $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        #If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo[-1].FileName
        & $WingetCmd source reset --force
        Write-ToLog $reset_string "green"

    }
    catch {
        Write-ToLog $fail_string "red"
        Update-StoreApps
    }

    #Remove WinGet MSIXBundle
    Remove-Item -Path $WingetInstaller -Force -ErrorAction SilentlyContinue
}
