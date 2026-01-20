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

        $MinVersion = [version]"14.50.0.0"

        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
            $osArch = "arm64"
        }
        elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
            $osArch = "x64"
        }
        else {
            $osArch = "x86"
        }

        $regPath = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$osArch"
        $needsInstall = $true

        if (Test-Path $regPath) {
            $v = Get-ItemProperty $regPath
            if ($v.Installed -eq 1 -and
                $null -ne $v.Major -and
                $null -ne $v.Minor -and
                $null -ne $v.Bld   -and
                $null -ne $v.Rbld) {
                try {
                    $ver = [version]"$($v.Major).$($v.Minor).$($v.Bld).$($v.Rbld)"
                    if ($ver -ge $MinVersion) {
                        Write-ToLog "VC++ $osArch already installed ($ver)" "Green"
                        $needsInstall = $false
                    }
                }
                catch {
                    Write-ToLog "VC++ $osArch registry version information is invalid. Forcing reinstall." "Yellow"
                }
            }
        }

        if ($needsInstall) {
            try {
                Write-ToLog "Installing VC++ Redistributable ($osArch)..."
                $VCRedistUrl = "https://aka.ms/vs/17/release/VC_redist.$osArch.exe"
                $installer = "$env:TEMP\VC_redist.$osArch.exe"

                Invoke-WebRequest $VCRedistUrl -OutFile $installer -UseBasicParsing
                Start-Process -FilePath $installer -ArgumentList "/quiet /norestart" -Wait
                Write-ToLog "VC++ $osArch installed successfully." "Green"
            }
            catch {
                Write-ToLog "Failed to install VC++ $osArch" "Red"
                throw
            }
            finally {
                Remove-Item $installer -ErrorAction SilentlyContinue
            }
        }



        # === Check Microsoft.VCLibs.140.00.UWPDesktop ===
        if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers)) {
            try {
                Write-ToLog "Microsoft.VCLibs.140.00.UWPDesktop is not installed" "Red"

                # Download VCLibs package
                $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.$osArch.14.00.Desktop.appx"
                $VCLibsFile = "$env:TEMP\Microsoft.VCLibs.$osArch.14.00.Desktop.appx"
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
                $UIXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$osArch.appx"
                $UIXamlFile = "$env:TEMP\Microsoft.UI.Xaml.2.8.$osArch.appx"
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
