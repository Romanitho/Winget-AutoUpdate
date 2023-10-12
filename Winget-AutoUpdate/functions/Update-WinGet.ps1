#Function to download and update WinGet

Function Update-WinGet ($WinGetAvailableVersion, $DownloadPath, $Log = $false) {

    #Download WinGet MSIXBundle
    switch ($Log) {
        $true {Write-ToLog "-> Downloading WinGet MSIXBundle for App Installer..."}
        Default {Write-Host "-> Downloading WinGet MSIXBundle for App Installer..."}
    }
    $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($WinGetURL, "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

    #Install WinGet MSIXBundle in SYSTEM context
    try {
        switch ($Log) {
            $true {Write-ToLog "-> Installing WinGet MSIXBundle for App Installer..."}
            Default {Write-Host "-> Installing WinGet MSIXBundle for App Installer..."}
        }
        Add-AppxProvisionedPackage -Online -PackagePath "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense | Out-Null
        switch ($Log) {
            $true {Write-ToLog "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully" "green"}
            Default {Write-host "WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully" -ForegroundColor Green}
        }

        #Reset WinGet Sources
        $ResolveWingetPath = Resolve-Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
        if ($ResolveWingetPath) {
            switch ($Log) {
                $true {Write-ToLog "-> WinGet sources reset." "green"}
                Default {Write-Host "-> WinGet sources reset." -ForegroundColor Green}
            }
            #If multiple version, pick last one
            $WingetPath = $ResolveWingetPath[-1].Path
            & $WingetPath source reset --force
        }
    }
    catch {
        switch ($Log) {
            $true {Write-ToLog "-> Failed to intall WinGet MSIXBundle for App Installer..." "red"}
            Default {Write-Host "Failed to intall WinGet MSIXBundle for App Installer..." -ForegroundColor Red}
        }
        Update-StoreApps
    }

    #Remove WinGet MSIXBundle
    Remove-Item -Path "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue
}
