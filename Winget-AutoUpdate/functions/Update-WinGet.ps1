#Function to download and update WinGet

Function Update-WinGet ($WinGetAvailableVersion, $DownloadPath) {

    $download_string = "-> Downloading WinGet MSIXBundle for App Installer..."
    $install_string = "-> Installing WinGet MSIXBundle for App Installer..."
    $success_string = "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully"
    $reset_string = "-> WinGet sources reset."
    $fail_string = "-> Failed to install WinGet MSIXBundle for App Installer..."

    #Download WinGet MSIXBundle
    Write-ToLog $download_string
    $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($WinGetURL, "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

    #Install WinGet MSIXBundle in SYSTEM context
    try {
        Write-ToLog $install_string
        Add-AppxProvisionedPackage -Online -PackagePath "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense | Out-Null
        Write-ToLog $success_string "green"

        #Reset WinGet Sources
        $ResolveWingetPath = Resolve-Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
        if ($ResolveWingetPath) {
            Write-ToLog $reset_string "green"
            #If multiple version, pick last one
            $WingetPath = $ResolveWingetPath[-1].Path
            & $WingetPath source reset --force
        }
    }
    catch {
        Write-ToLog $fail_string "red"
        Update-StoreApps
    }

    #Remove WinGet MSIXBundle
    Remove-Item -Path "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue
}
