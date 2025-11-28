<#
.SYNOPSIS
    Ensures all WinGet prerequisites are installed and up-to-date.

.DESCRIPTION
    Checks and installs the following prerequisites for WinGet:
    - Microsoft Visual C++ 2015-2022 Redistributable
    - Microsoft.VCLibs.140.00.UWPDesktop (UWP dependency)
    - Microsoft.UI.Xaml.2.8 (UI framework dependency)
    - WinGet CLI (App Installer) itself

.EXAMPLE
    Install-Prerequisites

.NOTES
    Must run with administrative privileges.
    Downloads installers from Microsoft's official sources.
    Falls back to Store update if WinGet installation fails.
#>
function Install-Prerequisites {

    try {

        Write-ToLog "Checking prerequisites..." "Yellow"

        # === Check Visual C++ 2015-2022 Redistributable ===
        $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
        $VisualMinVer = "14.40.0.0"
        $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2022 -and $_.GetValue("DisplayVersion") -gt $VisualMinVer }

        if (!($path)) {
            try {
                Write-ToLog "MS Visual C++ 2015-2022 is not installed" "Red"

                # Determine processor architecture for correct installer
                if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
                    $OSArch = "arm64"
                }
                elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
                    $OSArch = "x64"
                }
                else {
                    $OSArch = "x86"
                }

                # Download and install VC++ Redistributable
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

        # === Check Microsoft.VCLibs.140.00.UWPDesktop ===
        if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers)) {
            try {
                Write-ToLog "Microsoft.VCLibs.140.00.UWPDesktop is not installed" "Red"

                # Download VCLibs package
                $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
                $VCLibsFile = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
                Write-ToLog "-> Downloading Microsoft.VCLibs.140.00.UWPDesktop..."
                Invoke-WebRequest -Uri $VCLibsUrl -OutFile $VCLibsFile -UseBasicParsing

                # Install package
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

        # === Check Microsoft.UI.Xaml.2.8 ===
        if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -AllUsers)) {
            try {
                Write-ToLog "Microsoft.UI.Xaml.2.8 is not installed" "Red"

                # Download UI.Xaml package
                $UIXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                $UIXamlFile = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx"
                Write-ToLog "-> Downloading Microsoft.UI.Xaml.2.8..."
                Invoke-WebRequest -Uri $UIXamlUrl -OutFile $UIXamlFile -UseBasicParsing

                # Install package
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

        # === Check WinGet CLI ===
        try {
            # Get latest WinGet version from GitHub
            $WinGeturl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
            $WinGetAvailableVersion = ((Invoke-WebRequest $WinGeturl -UseBasicParsing | ConvertFrom-Json)[0].tag_name).TrimStart("v")
        }
        catch {
            # Fallback to known version if API fails
            $WinGetAvailableVersion = "1.11.430"
        }

        try {
            # Get currently installed WinGet version
            $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
            $WingetCmd = $WingetInfo[-1].FileName
            $WingetInstalledVersion = (& $WingetCmd -v).Trim().TrimStart("v")
        }
        catch {
            Write-ToLog "WinGet is not installed" "Red"
            $WinGetInstalledVersion = "0.0.0"
        }

        Write-ToLog "WinGet installed version: $WinGetInstalledVersion | WinGet available version: $WinGetAvailableVersion"

        # Install WinGet if outdated
        if ((Compare-SemVer -Version1 $WinGetInstalledVersion -Version2 $WinGetAvailableVersion) -lt 0) {
            try {
                # Download WinGet MSIXBundle
                Write-ToLog "-> Downloading WinGet MSIXBundle for App Installer..."
                $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                $WingetInstaller = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                Invoke-WebRequest -Uri $WinGetURL -OutFile $WingetInstaller -UseBasicParsing

                # Install WinGet
                Write-ToLog "-> Installing WinGet MSIXBundle for App Installer..."
                Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
                Write-ToLog "-> WinGet MSIXBundle (v$WinGetAvailableVersion) for App Installer installed successfully!" "green"

                # Reset WinGet sources after installation
                $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
                $WingetCmd = $WingetInfo[-1].FileName
                & $WingetCmd source reset --force
                Write-ToLog "-> WinGet sources reset." "green"
            }
            catch {
                Write-ToLog "-> Failed to install WinGet MSIXBundle for App Installer..." "red"
                # Try to update via Microsoft Store as fallback
                Update-StoreApps
            }

            # Cleanup installer
            Remove-Item -Path $WingetInstaller -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-ToLog "-> WinGet is up to date." "Green"
        }

        Write-ToLog "Prerequisites checked. OK" "Green"

    }
    catch {
        Write-ToLog "Prerequisites check failed" "Red"
    }

}
