function Install-Prerequisites {

    try {

        Write-ToLog "Checking prerequisites..." "Yellow"

        #Check if Visual C++ 2019 or 2022 installed
        $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
        $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
        $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022 }
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
                Invoke-WebRequest $SourceURL -UseBasicParsing -OutFile $Installer
                Write-ToLog "-> Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/passive /norestart" -Wait
                Start-Sleep 3
                Write-ToLog "-> MS Visual C++ 2015-2022 installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> MS Visual C++ 2015-2022 installation failed." "Red"
                Start-Sleep 3
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
                Invoke-RestMethod -Uri $VCLibsUrl -OutFile $VCLibsFile
                #Install
                Write-ToLog "-> Installing Microsoft.VCLibs.140.00.UWPDesktop..."
                Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense | Out-Null
                Write-ToLog "-> Microsoft.VCLibs.140.00.UWPDesktop installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> Failed to intall Microsoft.VCLibs.140.00.UWPDesktop..." "Red"
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
                Invoke-RestMethod -Uri $UIXamlUrl -OutFile $UIXamlFile
                #Install
                Write-ToLog "-> Installing Microsoft.UI.Xaml.2.8..."
                Add-AppxProvisionedPackage -Online -PackagePath $UIXamlFile -SkipLicense | Out-Null
                Write-ToLog "-> Microsoft.UI.Xaml.2.8 installed successfully." "Green"
            }
            catch {
                Write-ToLog "-> Failed to intall Microsoft.UI.Xaml.2.8..." "Red"
            }
            finally {
                Remove-Item -Path $UIXamlFile -Force
            }
        }

        Write-ToLog "Prerequisites checked. OK`n" "Green"

    }
    catch {

        Write-ToLog "Prerequisites checked failed`n" "Red"

    }


}