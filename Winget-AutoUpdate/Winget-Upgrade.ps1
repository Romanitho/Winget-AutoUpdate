<# LOAD FUNCTIONS #>

#Get Working Dir
$Script:WorkingDir = $PSScriptRoot
#Get Functions
Get-ChildItem "$WorkingDir\functions" | ForEach-Object { . $_.FullName }


<# MAIN #>

#Check if running account is system or interactive logon
$Script:IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem

#Run log initialisation function
Start-Init

#Get WAU Configurations
$Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"

#Log running context and more...
if ($IsSystem) {
    Write-Log "Running in System context"
    #Get WAU Policies and set the Configurations Registry Accordingly
    $WAUPolicies = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue
    if ($WAUPolicies) {
        if ($WAUPolicies.WAU_ActivateGPOManagement -eq 1) {
            Write-Log "Activated WAU GPO Management detected, comparing..."
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
            if ($null -ne $WAUPolicies.WAU_BypassListForUsers -and ($WAUPolicies.WAU_BypassListForUsers -ne $WAUConfig.WAU_BypassListForUsers)) {
                New-ItemProperty $regPath -Name WAU_BypassListForUsers -Value $WAUPolicies.WAU_BypassListForUsers -PropertyType DWord -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_BypassListForUsers) {
                Remove-ItemProperty $regPath"\" -Name WAU_BypassListForUsers -Force -ErrorAction SilentlyContinue | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_DisableAutoUpdate -and ($WAUPolicies.WAU_DisableAutoUpdate -ne $WAUConfig.WAU_DisableAutoUpdate)) {
                New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value $WAUPolicies.WAU_DisableAutoUpdate -PropertyType DWord -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_DisableAutoUpdate) {
                Remove-ItemProperty $regPath"\" -Name WAU_DisableAutoUpdate -Force -ErrorAction SilentlyContinue | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_DoNotRunOnMetered -and ($WAUPolicies.WAU_DoNotRunOnMetered -ne $WAUConfig.WAU_DoNotRunOnMetered)) {
                New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value $WAUPolicies.WAU_DoNotRunOnMetered -PropertyType DWord -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_DoNotRunOnMetered) {
                New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value 1 -PropertyType DWord -Force | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_UpdatePrerelease -and ($WAUPolicies.WAU_UpdatePrerelease -ne $WAUConfig.WAU_UpdatePrerelease)) {
                New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value $WAUPolicies.WAU_UpdatePrerelease -PropertyType DWord -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_UpdatePrerelease) {
                New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_UseWhiteList -and ($WAUPolicies.WAU_UseWhiteList -eq 1) -and ($WAUPolicies.WAU_UseWhiteList -ne $WAUConfig.WAU_UseWhiteList)) {
                New-ItemProperty $regPath -Name WAU_UseWhiteList -Value $WAUPolicies.WAU_UseWhiteList -PropertyType DWord -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_UseWhiteList -or $WAUPolicies.WAU_UseWhiteList -eq 0) {
                Remove-ItemProperty $regPath -Name WAU_UseWhiteList -Force -ErrorAction SilentlyContinue | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_ListPath -and ($WAUPolicies.WAU_ListPath -ne $WAUConfig.WAU_ListPath)) {
                New-ItemProperty $regPath -Name WAU_ListPath -Value $WAUPolicies.WAU_ListPath -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_ListPath) {
                Remove-ItemProperty $regPath"\" -Name WAU_ListPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
    
            if ($null -ne $WAUPolicies.WAU_ModsPath -and ($WAUPolicies.WAU_ModsPath -ne $WAUConfig.WAU_ModsPath)) {
                New-ItemProperty $regPath -Name WAU_ModsPath -Value $WAUPolicies.WAU_ModsPath -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_ModsPath) {
                Remove-ItemProperty $regPath"\" -Name WAU_ModsPath -Force -ErrorAction SilentlyContinue | Out-Null
            }

            if ($null -ne $WAUPolicies.WAU_NotificationLevel -and ($WAUPolicies.WAU_NotificationLevel -ne $WAUConfig.WAU_NotificationLevel)) {
                New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $WAUPolicies.WAU_NotificationLevel -Force | Out-Null
            }
            elseif ($null -eq $WAUPolicies.WAU_NotificationLevel) {
                New-ItemProperty $regPath -Name WAU_NotificationLevel -Value "Full" -Force | Out-Null
            }
        }
        #Get WAU Configurations after Policies change
        $Script:WAUConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate"
    }
    #Run post update actions if necessary if run as System
    if (!($WAUConfig.WAU_PostUpdateActions -eq 0)) {
        Invoke-PostUpdateActions
    }
    #Run Scope Machine funtion if run as System
    $SettingsPath = "$Env:windir\system32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    Add-ScopeMachine $SettingsPath
}
else {
    Write-Log "Running in User context"
}

#Get Notif Locale function
$LocaleDisplayName = Get-NotifLocale
Write-Log "Notification Level: $($WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan"

#Check network connectivity
if (Test-Network) {
    #Check if Winget is installed and get Winget cmd
    $TestWinget = Get-WingetCmd

    if ($TestWinget) {
        #Get Current Version
        $WAUCurrentVersion = $WAUConfig.DisplayVersion
        Write-Log "WAU current version: $WAUCurrentVersion"
        if ($IsSystem) {
            #Check if WAU update feature is enabled or not if run as System
            $WAUDisableAutoUpdate = $WAUConfig.WAU_DisableAutoUpdate
            #If yes then check WAU update if run as System
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

            #Delete previous list_/winget_error (if they exist) if run as System
            if (Test-Path "$WorkingDir\logs\error.txt") {
                Remove-Item "$WorkingDir\logs\error.txt" -Force
            }

            #Get External ListPath if run as System
            if ($WAUConfig.WAU_ListPath) {
                Write-Log "WAU uses External Lists from: $($WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/"))"
                $NewList = Test-ListPath $WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/") $WAUConfig.WAU_UseWhiteList $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                if ($NewList) {
                    Write-Log "Newer List downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))" "Yellow"
                }
                else {
                    if ((Test-Path "$WorkingDir\included_apps.txt") -or (Test-Path "$WorkingDir\excluded_apps.txt")) {
                        Write-Log "List is up to date." "Green"
                    }
                    else {
                        Write-Log "Critical: List doesn't exist, exiting..." "Red"
                        New-Item "$WorkingDir\logs\error.txt" -Value "List doesn't exist!" -Force
                        Exit 1
                    }
                }
            }

            #Get External ModsPath if run as System
            if ($WAUConfig.WAU_ModsPath) {
                Write-Log "WAU uses External Mods from: $($WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/"))"
                $NewMods, $DeletedMods = Test-ModsPath $WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/") $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                if ($NewMods -gt 0) {
                    Write-Log "$NewMods newer Mods downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))\mods" "Yellow"
                }
                else {
                    if (Test-Path "$WorkingDir\mods\*.ps1") {
                        Write-Log "Mods are up to date." "Green"
                    }
                    else {
                        Write-Log "No Mods are implemented..." "Yellow"
                    }
                }
                if ($DeletedMods -gt 0) {
                    Write-Log "$DeletedMods Mods deleted (not externally managed) from local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))\mods" "Red"
                }
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
        Write-Log "Checking application updates on Winget Repository..." "yellow"
        $outdated = Get-WingetOutdatedApps

        #If something is wrong with the winget source, exit
        if ($outdated -like "Problem:*") {
            Write-Log "Critical: An error occured, exiting..." "red"
            Write-Log "$outdated" "red"
            New-Item "$WorkingDir\logs\error.txt" -Value "$outdated" -Force
            Exit 1
        }

        #Log list of app to update
        foreach ($app in $outdated) {
            #List available updates
            $Log = "-> Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
            $Log | Write-host
            $Log | out-file -filepath $LogFile -Append
        }

        #Count good update installations
        $Script:InstallOK = 0

        #Trick under user context when -BypassListForUsers is used
        if ($IsSystem -eq $false -and $WAUConfig.WAU_BypassListForUsers -eq $true) {
            Write-Log "Bypass system list in user context is Enabled."
            $UseWhiteList = $false
            $toSkip = $null
        }

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

        #Run WAU in user context if currently as system and the user task exist
        $UserScheduledTask = Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue
        if ($IsSystem -and $UserScheduledTask) {

            #Get Winget system apps to excape them befor running user context
            Write-Log "Get list of installed Winget apps in System context..."
            Get-WingetSystemApps

            #Run user context scheduled task
            Write-Log "Starting WAU in User context"
            Start-ScheduledTask $UserScheduledTask.TaskName -ErrorAction SilentlyContinue
            Exit 0
        }
        elseif (!$UserScheduledTask){
            Write-Log "User context execution not installed"
        }
    }
    else {
        Write-Log "Critical: An error occured, exiting..." "red"
        New-Item "$WorkingDir\logs\error.txt" -Value "Winget not installed or detected!" -Force
        Exit 1
    }
}

#End
Write-Log "End of process!" "Cyan"
Start-Sleep 3
