function Install-Prerequisites {
	
	try {

		Write-ToLog "Checking prerequisites..." "Yellow"

		if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
			$OSArch = "arm64"
		}
		elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
			$OSArch = "x64"
		}
		else {
			$OSArch = "x86"
		}

		$ProgressPreference = "SilentlyContinue"
		$Path = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe"
		$Item = Get-Item -Path $Path
		$InstalledVersion = "0.0"

		if ($Item) {
			$Info = $Item.VersionInfo |
			Sort-Object -Property FileVersionRaw -Descending -Unique |
			Select-Object -First 1
			$Cmd = $Info.FileName
			$InstalledVersion = (& $Cmd -v | Select-String -Pattern '[\d\.]+').Matches.Value
		}

		$urlBase = "microsoft/winget-cli/releases"

		$AvailableVersion = (((Invoke-WebRequest -Uri "https://api.github.com/repos/$urlBase/latest" |
					ConvertFrom-Json).tag_name) | Select-String '[\d\.]+').Matches.Value

		# $AvailableVersion = [System.Version]::Parse($AvailableVersion)
		# $InstalledVersion = [System.Version]::Parse($InstalledVersion)

		if ($InstalledVersion -eq "0.0") {

			$url = "https://github.com/$urlBase/download/v$AvailableVersion"
			$urlDependencies = "$url/DesktopAppInstaller_Dependencies"

			$Installer = "$env:TEMP\DesktopAppInstaller_Dependencies"
			Invoke-WebRequest -Uri "$urlDependencies.zip" -OutFile "$Installer.zip"
			Expand-Archive -Path "$Installer.zip" -DestinationPath $Installer -Force

			$Dependencies = Invoke-WebRequest -Uri "$urlDependencies.json" | ConvertFrom-Json
		
			$Dependencies.Dependencies | ForEach-Object {

				$Package = Get-AppxPackage -Name $_.Name -AllUsers |
				Where-Object { $_.PackageUserInformation -match "Installed" }
			
				if (!$Package) {

					$Package = (Get-Item -Path "$Installer/$OSArch/$($_.Name)*").FullName
					Add-AppxProvisionedPackage -Online -PackagePath $Package -SkipLicense | Out-Null
				}
			}

			Remove-Item -Path "$Installer*" -Recurse -Force

			$msixbundle = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
			Invoke-WebRequest -Uri "$url/$msixbundle" -OutFile "$env:TEMP\$msixbundle"
			Add-AppxProvisionedPackage -Online -PackagePath "$env:TEMP\$msixbundle" -SkipLicense | Out-Null
			Remove-Item -Path "$env:TEMP\$msixbundle" -Force
		}

		$WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo |
		Sort-Object -Property FileVersionRaw -Descending -Unique | Select-Object -First 1
		$WingetCmd = $WingetInfo.FileName

		& $WingetCmd upgrade --all --accept-package-agreements --accept-source-agreements --disable-interactivity --silent

		$Visual2022 = Get-CimInstance -ClassName "Win32_Product" | Where-Object Name -Like "Microsoft Visual C++ * $OSArch*"
	
		if (!$Visual2022) {
			& $WingetCmd install --id "Microsoft.VCRedist.2015+.$OSArch" --source "winget" --scope "machine" --disable-interactivity --silent
		}

		$ProgressPreference = "Continue"

	}
	catch {

		Write-ToLog "Prerequisites checked failed" "Red"

	}
}
