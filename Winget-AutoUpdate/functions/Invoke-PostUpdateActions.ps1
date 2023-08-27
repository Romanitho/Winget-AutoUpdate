#Function to make actions after WAU update

function Invoke-PostUpdateActions {

    #log
    Write-ToLog "Running Post Update actions:" "yellow"

    #Check if Intune Management Extension Logs folder and WAU-updates.log exists, make symlink
    if ((Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs") -and !(Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log")) {
        Write-ToLog "-> Creating SymLink for log file in Intune Management Extension log folder" "yellow"
        New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue | Out-Null
    }
    #Check if Intune Management Extension Logs folder and WAU-install.log exists, make symlink
    if ((Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs") -and (Test-Path "$WorkingDir\logs\install.log") -and !(Test-Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log")) {
        Write-host "`nCreating SymLink for log file (WAU-install) in Intune Management Extension log folder" -ForegroundColor Yellow
        New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ItemType SymbolicLink -Value "$WorkingDir\logs\install.log" -Force -ErrorAction SilentlyContinue | Out-Null
    }

    #Check Winget Package Installed version
    Write-ToLog "-> Checking if Winget is installed/up to date"
    $TestWinGet = Get-AppXPackage -Name 'Microsoft.DesktopAppInstaller'

    #Current: v1.5.2201 = 1.20.2201.0
    If ([Version]$TestWinGet.Version -ge "1.20.2201.0") {

        Write-ToLog "-> WinGet is installed/up to date" "green"

    }
    Else {

        #Download WinGet MSIXBundle
        Write-ToLog "-> Downloading Winget MSIXBundle for App Installer..."
        $WinGetURL = "https://github.com/microsoft/winget-cli/releases/download/v1.5.2201/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($WinGetURL, "$($WAUConfig.InstallLocation)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

        #Install WinGet MSIXBundle
        try {
            Write-ToLog "-> Installing Winget MSIXBundle for App Installer..."
            Add-AppxPackage -Path "$($WAUConfig.InstallLocation)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" | Out-Null
            Write-ToLog "-> Installed Winget MSIXBundle for App Installer" "green"
        }
        catch {
            Write-ToLog "-> Failed to intall Winget MSIXBundle for App Installer..." "red"
        }

        #Remove WinGet MSIXBundle
        Remove-Item -Path "$($WAUConfig.InstallLocation)\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue

    }

    #Reset Winget Sources
    $ResolveWingetPath = Resolve-Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
        & $WingetPath source reset --force

        #log
        Write-ToLog "-> Winget sources reseted." "green"
    }

    #Create WAU Regkey if not present
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
    if (!(test-path $regPath)) {
        New-Item $regPath -Force
        New-ItemProperty $regPath -Name DisplayName -Value "Winget-AutoUpdate (WAU)" -Force
        New-ItemProperty $regPath -Name DisplayIcon -Value "C:\Windows\System32\shell32.dll,-16739" -Force
        New-ItemProperty $regPath -Name NoModify -Value 1 -Force
        New-ItemProperty $regPath -Name NoRepair -Value 1 -Force
        New-ItemProperty $regPath -Name Publisher -Value "Romanitho" -Force
        New-ItemProperty $regPath -Name URLInfoAbout -Value "https://github.com/Romanitho/Winget-AutoUpdate" -Force
        New-ItemProperty $regPath -Name InstallLocation -Value $WorkingDir -Force
        New-ItemProperty $regPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force
        New-ItemProperty $regPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force
        New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force

        #log
        Write-ToLog "-> $regPath created." "green"
    }
    #Fix Notif where WAU_NotificationLevel is not set
    $regNotif = Get-ItemProperty $regPath -Name WAU_NotificationLevel -ErrorAction SilentlyContinue
    if (!$regNotif) {
        New-ItemProperty $regPath -Name WAU_NotificationLevel -Value Full -Force

        #log
        Write-ToLog "-> Notification level setting was missing. Fixed with 'Full' option."
    }

    #Set WAU_MaxLogFiles/WAU_MaxLogSize if not set
    $MaxLogFiles = Get-ItemProperty $regPath -Name WAU_MaxLogFiles -ErrorAction SilentlyContinue
    if (!$MaxLogFiles) {
        New-ItemProperty $regPath -Name WAU_MaxLogFiles -Value 3 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $regPath -Name WAU_MaxLogSize -Value 1048576 -PropertyType DWord -Force | Out-Null

        #log
        Write-ToLog "-> MaxLogFiles/MaxLogSize setting was missing. Fixed with 3/1048576 (in bytes, default is 1048576 = 1 MB)."
    }

    #Set WAU_ListPath if not set
    $ListPath = Get-ItemProperty $regPath -Name WAU_ListPath -ErrorAction SilentlyContinue
    if (!$ListPath) {
        New-ItemProperty $regPath -Name WAU_ListPath -Force | Out-Null

        #log
        Write-ToLog "-> ListPath setting was missing. Fixed with empty string."
    }

    #Set WAU_ModsPath if not set
    $ModsPath = Get-ItemProperty $regPath -Name WAU_ModsPath -ErrorAction SilentlyContinue
    if (!$ModsPath) {
        New-ItemProperty $regPath -Name WAU_ModsPath -Force | Out-Null

        #log
        Write-ToLog "-> ModsPath setting was missing. Fixed with empty string."
    }

    #Security check
    Write-ToLog "-> Checking Mods Directory:" "yellow"
    $Protected = Invoke-ModsProtect "$($WAUConfig.InstallLocation)\mods"
    if ($Protected -eq $True) {
        Write-ToLog "-> The mods directory is now secured!" "green"
    }
    elseif ($Protected -eq $False) {
        Write-ToLog "-> The mods directory was already secured!" "green"
    }
    else {
        Write-ToLog "-> Error: The mods directory couldn't be verified as secured!" "red"
    }

    #Convert about.xml if exists (old WAU versions) to reg
    $WAUAboutPath = "$WorkingDir\config\about.xml"
    if (test-path $WAUAboutPath) {
        [xml]$About = Get-Content $WAUAboutPath -Encoding UTF8 -ErrorAction SilentlyContinue
        New-ItemProperty $regPath -Name DisplayVersion -Value $About.app.version -Force

        #Remove file once converted
        Remove-Item $WAUAboutPath -Force -Confirm:$false

        #log
        Write-ToLog "-> $WAUAboutPath converted." "green"
    }

    #Convert config.xml if exists (previous WAU versions) to reg
    $WAUConfigPath = "$WorkingDir\config\config.xml"
    if (test-path $WAUConfigPath) {
        [xml]$Config = Get-Content $WAUConfigPath -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($Config.app.WAUautoupdate -eq "False") { New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force }
        if ($Config.app.NotificationLevel) { New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $Config.app.NotificationLevel -Force }
        if ($Config.app.UseWAUWhiteList -eq "True") { New-ItemProperty $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force }
        if ($Config.app.WAUprerelease -eq "True") { New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force }

        #Remove file once converted
        Remove-Item $WAUConfigPath -Force -Confirm:$false

        #log
        Write-ToLog "-> $WAUConfigPath converted." "green"
    }

    #Remove old functions / files
    $FileNames = @(
        "$WorkingDir\functions\Get-WAUConfig.ps1",
        "$WorkingDir\functions\Get-WAUCurrentVersion.ps1",
        "$WorkingDir\functions\Get-WAUUpdateStatus.ps1",
        "$WorkingDir\functions\Write-Log.ps1",
        "$WorkingDir\Version.txt"
    )
    foreach ($FileName in $FileNames) {
        if (Test-Path $FileName) {
            Remove-Item $FileName -Force -Confirm:$false

            #log
            Write-ToLog "-> $FileName removed." "green"
        }
    }

    #Remove old registry key
    $RegistryKeys = @(
        "VersionMajor",
        "VersionMinor"
    )
    foreach ($RegistryKey in $RegistryKeys) {
        if (Get-ItemProperty -Path $regPath -Name $RegistryKey -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $regPath -Name $RegistryKey
        }
    }

    #Reset WAU_UpdatePostActions Value
    $WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 0 -Force

    #Get updated WAU Config
    $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

    #log
    Write-ToLog "Post Update actions finished" "green"

}
