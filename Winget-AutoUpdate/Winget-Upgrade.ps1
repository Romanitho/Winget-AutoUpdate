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

    #Get and set Domain/Local Policies (GPO)
    $ActivateGPOManagement, $ChangedSettings = Get-Policies
    if ($ActivateGPOManagement) {
        Write-Log "Activated WAU GPO Management detected, comparing..."
        if ($null -ne $ChangedSettings -and $ChangedSettings -ne 0) {
            Write-Log "Changed settings detected and applied" "Yellow"
        }
        else {
            Write-Log "No Changed settings detected" "Yellow"
        }
    }

    # Maximum number of log files to keep. Default is 3. Setting MaxLogFiles to 0 will keep all log files.
    $MaxLogFiles = $WAUConfig.WAU_MaxLogFiles
    if ($null -eq $MaxLogFiles) {
        [int32] $MaxLogFiles = 3
    }
    else {
        [int32] $MaxLogFiles = $MaxLogFiles
    }
    
    # Maximum size of log file.
    $MaxLogSize = $WAUConfig.WAU_MaxLogSize
    if (!$MaxLogSize) {
        [int64] $MaxLogSize = 1048576 # in bytes, default is 1048576 = 1 MB
    }
    else {
        [int64] $MaxLogSize = $MaxLogSize
    }

    #LogRotation if System
    $LogRotate = Invoke-LogRotation $LogFile $MaxLogFiles $MaxLogSize
    if ($LogRotate -eq $False) {
        Write-Log "An Exception occured during Log Rotation..."
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
                if ($($WAUConfig.WAU_ListPath) -ne "GPO") {
                    $NewList = Test-ListPath $WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/") $WAUConfig.WAU_UseWhiteList $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                    if ($ReachNoPath) {
                        Write-Log "Couldn't reach/find/compare/copy from $($WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/"))..." "Red"
                        $Script:ReachNoPath = $False
                    }
                    if ($NewList) {
                        Write-Log "Newer List downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))" "Yellow"
                    }
                    else {
                        if ($WAUConfig.WAU_UseWhiteList -and (Test-Path "$WorkingDir\included_apps.txt")) {
                            Write-Log "List (white) is up to date." "Green"
                        }
                        elseif (!$WAUConfig.WAU_UseWhiteList -and (Test-Path "$WorkingDir\excluded_apps.txt")) {
                            Write-Log "List (black) is up to date." "Green"
                        }
                        else {
                            Write-Log "Critical: White/Black List doesn't exist, exiting..." "Red"
                            New-Item "$WorkingDir\logs\error.txt" -Value "White/Black List doesn't exist" -Force
                            Exit 1
                        }
                    }
                }
            }
    
            #Get External ModsPath if run as System
            if ($WAUConfig.WAU_ModsPath) {
                Write-Log "WAU uses External Mods from: $($WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/"))"
                $NewMods, $DeletedMods = Test-ModsPath $WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/") $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                if ($ReachNoPath) {
                    Write-Log "Couldn't reach/find/compare/copy from $($WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/"))..." "Red"
                    $Script:ReachNoPath = $False
                }
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

        if ($($WAUConfig.WAU_ListPath) -eq "GPO") {
            $Script:GPOList = $True
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

        #Fix and count the array if GPO List as ERROR handling!
        if ($GPOList) {
            if ($UseWhiteList) {
                $WhiteList = $toUpdate.GetUpperBound(0)
                if ($null -eq $WhiteList) {
                    Write-Log "Critical: Whitelist doesn't exist in GPO, exiting..." "Red"
                    New-Item "$WorkingDir\logs\error.txt" -Value "Whitelist doesn't exist in GPO" -Force
                    Exit 1
                }
                $toUpdate = $toUpdate.Data
            }
            else {
                $BlackList = $toSkip.GetUpperBound(0)
                if ($null -eq $BlackList) {
                    Write-Log "Critical: Blacklist doesn't exist in GPO, exiting..." "Red"
                    New-Item "$WorkingDir\logs\error.txt" -Value "Blacklist doesn't exist in GPO" -Force
                    Exit 1
                }
                $toSkip = $toSkip.Data
            }
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

        #Check if any user is logged on if System and run User task (if installed)
        if ($IsSystem) {
            #User check routine from: https://stackoverflow.com/questions/23219718/powershell-script-to-see-currently-logged-in-users-domain-and-machine-status
            $explorerprocesses = @(Get-WmiObject -Query "Select * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
            If ($explorerprocesses.Count -eq 0)
            {
                Write-Log "No explorer process found / Nobody interactively logged on.. ..exiting"
                Exit 0
            }
            Else
            {
                #Run WAU in user context if the user task exist
                $UserScheduledTask = Get-ScheduledTask -TaskName "Winget-AutoUpdate-UserContext" -ErrorAction SilentlyContinue
                if ($UserScheduledTask) {

                    #Get Winget system apps to excape them befor running user context
                    Write-Log "User logged on, get a list of installed Winget apps in System context..."
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
        }
    }
    else {
        Write-Log "Critical: Winget not installed or detected, exiting..." "red"
        New-Item "$WorkingDir\logs\error.txt" -Value "Winget not installed or detected" -Force
        Exit 1
    }
}

#End
Write-Log "End of process!" "Cyan"
Start-Sleep 3
