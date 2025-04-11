function Install-Prerequisites {

    try {

        Write-ToLog "Checking prerequisites..." "Yellow"

        #Check if Visual C++ 2022 is installed
        $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
        $VisualMinVer = "14.40.0.0"
        $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2022 -and $_.GetValue("DisplayVersion") -gt $VisualMinVer }
        if (!($path)) {
            try {
                Write-ToLog "MS Visual C++ 2015-2022 is not installed" "Red"

                #Get proc architecture
                if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
                    $OSArch = "arm64"
                }
                elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
                    $OSArch = "x64"
                }
                else {
                    $OSArch = "x86"
                }

                #Download and install
                $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
                $Installer = "$env:TEMP\VC_redist.$OSArch.exe"
                Write-ToLog "-> Downloading $SourceURL..."
                Invoke-WebRequest $SourceURL -OutFile $Installer -UseBasicParsing
                Write-ToLog "-> Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
                Write-ToLog "-> MS Visual C++ 2015-2022 installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> MS Visual C++ 2015-2022 installation failed." "Red"
            }
            finally {
                Remove-Item $Installer -ErrorAction Ignore
            }
        }

        #Check if Microsoft.VCLibs.140.00.UWPDesktop is installed
        if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers)) {
            try {
                Write-ToLog "Microsoft.VCLibs.140.00.UWPDesktop is not installed" "Red"
                #Download
                $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
                $VCLibsFile = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
                Write-ToLog "-> Downloading Microsoft.VCLibs.140.00.UWPDesktop..."
                Invoke-WebRequest -Uri $VCLibsUrl -OutFile $VCLibsFile -UseBasicParsing
                #Install
                Write-ToLog "-> Installing Microsoft.VCLibs.140.00.UWPDesktop..."
                Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense | Out-Null
                Write-ToLog "-> Microsoft.VCLibs.140.00.UWPDesktop installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> Failed to install Microsoft.VCLibs.140.00.UWPDesktop..." "Red"
            }
            finally {
                Remove-Item -Path $VCLibsFile -Force
            }
        }

        #Check if Microsoft.UI.Xaml.2.8 is installed
        if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -AllUsers)) {
            try {
                Write-ToLog "Microsoft.UI.Xaml.2.8 is not installed" "Red"
                #Download
                $UIXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                $UIXamlFile = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx"
                Write-ToLog "-> Downloading Microsoft.UI.Xaml.2.8..."
                Invoke-WebRequest -Uri $UIXamlUrl -OutFile $UIXamlFile -UseBasicParsing
                #Install
                Write-ToLog "-> Installing Microsoft.UI.Xaml.2.8..."
                Add-AppxProvisionedPackage -Online -PackagePath $UIXamlFile -SkipLicense | Out-Null
                Write-ToLog "-> Microsoft.UI.Xaml.2.8 installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> Failed to install Microsoft.UI.Xaml.2.8..." "Red"
            }
            finally {
                Remove-Item -Path $UIXamlFile -Force
            }
        }

        #Check if Winget is installed (and up to date)
        try {
            #Get latest WinGet info
            $WinGeturl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
            $WinGetAvailableVersion = ((Invoke-WebRequest $WinGeturl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).TrimStart("v")
        }
        catch {
            #If fail set version to the latest version as of 2025-03-14
            $WinGetAvailableVersion = "1.10.340"
        }
        try {
            #Get Admin Context Winget Location
            $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
            #If multiple versions, pick most recent one
            $WingetCmd = $WingetInfo[-1].FileName
            #Get current Winget Version
            $WingetInstalledVersion = (& $WingetCmd -v).Trim().TrimStart("v")
        }
        catch {
            Write-ToLog "WinGet is not installed" "Red"
            $WinGetInstalledVersion = "0.0.0"
        }
        Write-ToLog "WinGet installed version: $WinGetInstalledVersion | WinGet available version: $WinGetAvailableVersion"
        #Check if the currently installed version is less than the available version
        if ((Compare-SemVer -Version1 $WinGetInstalledVersion -Version2 $WinGetAvailableVersion) -lt 0) {
            #Install WinGet MSIXBundle in SYSTEM context
            try {
                #Download WinGet MSIXBundle
                Write-ToLog "-> Downloading WinGet MSIXBundle for App Installer..."
                $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $WingetInstaller = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                Invoke-WebRequest -Uri $WinGetURL -OutFile $WingetInstaller -UseBasicParsing

                #Install
                Write-ToLog "-> Installing WinGet MSIXBundle for App Installer..."
                Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
                Write-ToLog "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully!" "green"

                #Reset WinGet Sources
                $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
                #If multiple versions, pick most recent one
                $WingetCmd = $WingetInfo[-1].FileName
                & $WingetCmd source reset --force
                Write-ToLog "-> WinGet sources reset." "green"
            }
            catch {
                Write-ToLog "-> Failed to install WinGet MSIXBundle for App Installer..." "red"
                #Force Store Apps to update
                Update-StoreApps
            }

            #Remove WinGet MSIXBundle
            Remove-Item -Path $WingetInstaller -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-ToLog "-> WinGet is up to date: v$WinGetInstalledVersion" "Green"
        }

        # Check if PowerShell module Microsoft.WinGet.Client is installed and up to date
        $moduleName = "Microsoft.WinGet.Client"
        $Script:winGetModuleAvailable = $false

        Write-ToLog "Checking if PowerShell module '$moduleName' is installed and up to date..." "Yellow"

        try {
            $installedModule = Get-InstalledModule -Name $moduleName -ErrorAction Stop
            try {
                $availableModule = Find-Module -Name $moduleName -ErrorAction Stop

                if ($availableModule.Version -gt $installedModule.Version) {
                    Write-ToLog "-> Updating '$moduleName' from version $($installedModule.Version) to $($availableModule.Version)..." "Yellow"
                    Update-Module -Name $moduleName -Force -ErrorAction Stop
                    Write-ToLog "-> Module '$moduleName' updated successfully." "Green"
                }
                else {
                    Write-ToLog "-> Module '$moduleName' is already up to date (version $($installedModule.Version))." "Green"
                }

                $Script:winGetModuleAvailable = $true
            }
            catch {
                Write-ToLog "-> Failed to check or update '$moduleName'. Error: $_" "Red"
            }
        }
        catch {
            Write-ToLog "-> Module '$moduleName' is not installed. Attempting installation..." "Red"
            try {
                Install-Module -Name $moduleName -Scope AllUsers -Force -ErrorAction Stop
                Write-ToLog "-> Module '$moduleName' installed successfully." "Green"
                if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
                    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
                }
                $Script:winGetModuleAvailable = $true
            }
            catch {
                Write-ToLog "-> Failed to install/import '$moduleName'. Error: $_" "Red"
            }
        }

        if ($Script:winGetModuleAvailable) {
            Write-ToLog "PowerShell module '$moduleName' is available." "Green"
        }
        else {
            Write-ToLog "PowerShell module '$moduleName' is NOT available. Using winget cmd commands instead." "Red"
        }

        Write-ToLog "Prerequisites checked. OK" "Green"

    }
    catch {

        Write-ToLog "Prerequisites checked failed" "Red"

    }


}
