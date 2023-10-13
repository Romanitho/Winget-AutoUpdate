#Function to download and update WinGet

Function Update-WinGet ($WinGetAvailableVersion, $DownloadPath, $Log = $false) {

	$download_string = "-> Downloading WinGet MSIXBundle for App Installer..."
	$install_string = "-> Installing WinGet MSIXBundle for App Installer..."
	$success_string = "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully"
	$reset_string = "-> WinGet sources reset."
	$fail_string = "-> Failed to intall WinGet MSIXBundle for App Installer..."

    #Download WinGet MSIXBundle
    switch ($Log) {
        $true {Write-ToLog $download_string}
        Default {Write-Host $download_string}
    }
    $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($WinGetURL, "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

    #Install WinGet MSIXBundle in SYSTEM context
    try {
        switch ($Log) {
            $true {Write-ToLog $install_string}
            Default {Write-Host $install_string}
        }
        Add-AppxProvisionedPackage -Online -PackagePath "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense | Out-Null
        switch ($Log) {
            $true {Write-ToLog $success_string "green"}
            Default {Write-host $success_string -ForegroundColor Green}
        }

        #Reset WinGet Sources
        $ResolveWingetPath = Resolve-Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
        if ($ResolveWingetPath) {
            switch ($Log) {
                $true {Write-ToLog $reset_string "green"}
                Default {Write-Host $reset_string -ForegroundColor Green}
            }
            #If multiple version, pick last one
            $WingetPath = $ResolveWingetPath[-1].Path
            & $WingetPath source reset --force
        }
        Update-StoreApps
    }
    catch {
        switch ($Log) {
            $true {Write-ToLog $fail_string "red"}
            Default {Write-Host $fail_string -ForegroundColor Red}
        }
        Update-StoreApps
    }

    #Remove WinGet MSIXBundle
    Remove-Item -Path "$DownloadPath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue
}
