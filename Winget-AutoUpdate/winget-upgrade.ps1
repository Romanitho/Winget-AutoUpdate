﻿<# LOAD FUNCTIONS #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot
#Get Functions
Get-ChildItem "$WorkingDir\functions" | ForEach-Object { . $_.FullName }


<# MAIN #>

#Run log initialisation function
Start-Init

#Get WAU Configurations
$Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

#Run post update actions if necessary
if (!($WAUConfig.WAU_PostUpdateActions -eq 0)) {
    Invoke-PostUpdateActions
}

#Run Scope Machine funtion if run as system
if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    $SettingsPath = "$Env:windir\system32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    Add-ScopeMachine $SettingsPath
}

#Get Notif Locale function
Get-NotifLocale

#Check network connectivity
if (Test-Network) {
    #Check if Winget is installed and get Winget cmd
    $TestWinget = Get-WingetCmd
    
    if ($TestWinget) {
        #Get Current Version
        $WAUCurrentVersion = $WAUConfig.DisplayVersion
        Write-Log "WAU current version: $WAUCurrentVersion"
        #Check if WAU update feature is enabled or not
        $WAUDisableAutoUpdate = $WAUConfig.WAU_DisableAutoUpdate
        #If yes then check WAU update
        if ($WAUDisableAutoUpdate -eq 1) {
            Write-Log "WAU AutoUpdate is Disabled." "Grey"
        }
        else {
            Write-Log "WAU AutoUpdate is Enabled." "Green"
            #Get Available Version
            $WAUAvailableVersion = Get-WAUAvailableVersion
            #Compare
            if ([version]$WAUAvailableVersion -gt [version]$WAUCurrentVersion) {
                #If new version is available, update it
                Write-Log "WAU Available version: $WAUAvailableVersion" "Yellow"
                Update-WAU
            }
            else {
                Write-Log "WAU is up to date." "Green"
            }
        }

        #Get External ListPath
        if ($WAUConfig.WAU_ListPath) {
            Write-Log "WAU uses External Lists from: $($WAUConfig.WAU_ListPath)"
            $NewList = Test-ListPath $WAUConfig.WAU_ListPath $WAUConfig.WAU_UseWhiteList $WAUConfig.InstallLocation
            if ($NewList) {
                Write-Log "Newer List copied/downloaded to local path: $($WAUConfig.InstallLocation)" "Yellow"
            }
            else {
                Write-Log "List is up to date." "Green"
            }
        }

        #Get White or Black list
        if ($WAUConfig.WAU_UseWhiteList -eq 1) {
            Write-Log "WAU uses White List config"
            $toUpdate = Get-IncludedApps
            $UseWhiteList = $true
        }
        else {
            Write-Log "WAU uses Black List config"
            $toSkip = Get-ExcludedApps
        }

        #Get outdated Winget packages
        $outdated = Get-WingetOutdatedApps

        #Log list of app to update
        foreach ($app in $outdated) {
            #List available updates
            $Log = "-> Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
            $Log | Write-host
            $Log | out-file -filepath $LogFile -Append
        }
        
        #Count good update installations
        $Script:InstallOK = 0

        #If White List
        if ($UseWhiteList) {
            #For each app, notify and update
            foreach ($app in $outdated) {
                if (($toUpdate -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                    Update-App $app
                }
                #if current app version is unknown
                elseif ($($app.Version) -eq "Unknown") {
                    Write-Log "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
                }
                #if app is in "excluded list"
                else {
                    Write-Log "$($app.Name) : Skipped upgrade because it is not in the included app list" "Gray"
                }
            }
        }
        #If Black List or default
        else {
            #For each app, notify and update
            foreach ($app in $outdated) {
                if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown") {
                    Update-App $app
                }
                #if current app version is unknown
                elseif ($($app.Version) -eq "Unknown") {
                    Write-Log "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
                }
                #if app is in "excluded list"
                else {
                    Write-Log "$($app.Name) : Skipped upgrade because it is in the excluded app list" "Gray"
                }
            }
        }
        
        if ($InstallOK -gt 0) {
            Write-Log "$InstallOK apps updated ! No more update." "Green"
        }
        if ($InstallOK -eq 0) {
            Write-Log "No new update." "Green"
        }
    }
}


#Run WAU in user context if currently as system
if ($currentPrincipal -eq $false) {
    Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
}

#End
Write-Log "End of process!" "Cyan"
Start-Sleep 3