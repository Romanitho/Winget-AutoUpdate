#Function to make actions after WAU update

function Invoke-PostUpdateActions {

    #log
    Write-ToLog "Running Post Update actions:" "yellow"

    # Check if Intune Management Extension Logs folder and WAU-updates.log exists, make symlink
    if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs" -ErrorAction SilentlyContinue) -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ErrorAction SilentlyContinue)) {
        Write-ToLog "-> Creating SymLink for log file (WAU-updates) in Intune Management Extension log folder" "yellow"
        $null = New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue
    }

    # Check if Intune Management Extension Logs folder and WAU-install.log exists, make symlink
    if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs" -ErrorAction SilentlyContinue) -and (Test-Path -Path ('{0}\logs\install.log' -f $WorkingDir) -ErrorAction SilentlyContinue) -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ErrorAction SilentlyContinue)) {
        Write-ToLog "-> Creating SymLink for log file (WAU-install) in Intune Management Extension log folder" "yellow"
        $null = (New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ItemType SymbolicLink -Value ('{0}\logs\install.log' -f $WorkingDir) -Force -Confirm:$False -ErrorAction SilentlyContinue)
    }

    Write-ToLog "-> Checking if WinGet is installed/up to date" "yellow"

    #Check available WinGet version, if fail set version to the latest version as of 2023-10-08
    $WinGetAvailableVersion = Get-WinGetAvailableVersion
    if (!$WinGetAvailableVersion) {
        $WinGetAvailableVersion = "1.6.2771"
    }

    #Check installed WinGet version
    $ResolveWingetPath = Resolve-Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
        $WinGetInstalledVersion = & $WingetPath --version
        $WinGetInstalledVersion = $WinGetInstalledVersion.Replace("v", "")
    }

    #Check if the current available WinGet isn't a Pre-release and if it's newer than the installed
    if (!($WinGetAvailableVersion -match "-pre") -and ($WinGetAvailableVersion -gt $WinGetInstalledVersion)) {
        Write-ToLog "-> WinGet is not installed/up to date (v$WinGetInstalledVersion) - v$WinGetAvailableVersion is available:" "red"
        Update-WinGet $WinGetAvailableVersion $($WAUConfig.InstallLocation) $true
    }
    elseif ($WinGetAvailableVersion -match "-pre") {
        Write-ToLog "-> WinGet is probably up to date (v$WinGetInstalledVersion) - v$WinGetAvailableVersion is available but only as a Pre-release" "yellow"
        Update-StoreApps $true
    }
    else {
        Write-ToLog "-> WinGet is up to date: v$WinGetInstalledVersion" "green"
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

    #Activate WAU in user context if previously configured (as "Winget-AutoUpdate-UserContext" at root)
    $UserContextTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -TaskPath '\' -ErrorAction SilentlyContinue
    if ($UserContextTask) {
        #Remove Winget-AutoUpdate-UserContext at root.
        Unregister-ScheduledTask $UserContextTask -Confirm:$False

        #Set it in registry as activated.
        New-ItemProperty $regPath -Name WAU_UserContext -Value 1 -PropertyType DWord -Force | Out-Null
        Write-ToLog "-> Old User Context task deleted and set to 'enabled' in registry."
    }


    ### End of post update actions ###

    #Reset WAU_UpdatePostActions Value
    $WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 0 -Force

    #Get updated WAU Config
    $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

    #log
    Write-ToLog "Post Update actions finished" "green"

}
