#region LOAD FUNCTIONS
# Get the Working Dir
[string]$Script:WorkingDir = $PSScriptRoot

# Get Functions
Get-ChildItem -Path "$($Script:WorkingDir)\functions" -File -Filter "*.ps1" -Depth 0 | ForEach-Object { . $_.FullName }
#endregion LOAD FUNCTIONS

#region INITIALIZATION
# Config console output encoding
$null = & "$env:WINDIR\System32\cmd.exe" /c ""
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

# Set GitHub Repo
[string]$Script:GitHub_Repo = "Winget-AutoUpdate"

# Log initialization
[string]$LogFile = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'updates.log')
#endregion INITIALIZATION

#region CONTEXT
# Check if running account is system or interactive logon System(default) otherwise User
[bool]$Script:IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem

# Check for current session ID (O = system without ServiceUI)
[Int32]$Script:SessionID = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
#endregion CONTEXT

#region EXECUTION CONTEXT AND LOGGING
# Preparation to run in current context
if ($true -eq $IsSystem) {

    #If log file doesn't exist, force create it
    if (!(Test-Path -Path $LogFile)) {
        Write-ToLog "New log file created"
    }

    #Check if running with session ID 0
    if ($SessionID -eq 0) {
        #Check if ServiceUI exists
        [string]$ServiceUIexe = [System.IO.Path]::Combine($Script:WorkingDir, 'ServiceUI.exe')
        [bool]$IsServiceUI = Test-Path $ServiceUIexe -PathType Leaf
        if ($true -eq $IsServiceUI) {
            #Check if any connected user
            $explorerprocesses = @(Get-CimInstance -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
            if ($explorerprocesses.Count -gt 0) {
                Write-ToLog "Rerun WAU in system context with ServiceUI"
                Start-Process `
                    -FilePath $ServiceUIexe `
                    -ArgumentList "-process:explorer.exe $env:windir\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1" `
                    -WorkingDirectory $WorkingDir
                Wait-Process "ServiceUI" -ErrorAction SilentlyContinue
                Exit 0
            }
            else {
                Write-ToLog -LogMsg "CHECK FOR APP UPDATES (System context)" -IsHeader
            }
        }
        else {
            Write-ToLog -LogMsg "CHECK FOR APP UPDATES (System context - No ServiceUI)" -IsHeader
        }
    }
    else {
        Write-ToLog -LogMsg "CHECK FOR APP UPDATES (System context - Connected user)" -IsHeader
    }
}
else {
    Write-ToLog -LogMsg "CHECK FOR APP UPDATES (User context)" -IsHeader
}
#endregion EXECUTION CONTEXT AND LOGGING

#region CONFIG & POLICIES
Write-ToLog "Reading WAUConfig"
$Script:WAUConfig = Get-WAUConfig
#endregion CONFIG & POLICIES

#region WINGET SOURCE
# Defining a custom source even if not used below (failsafe suggested by github/sebneus mentioned in issues/823)
[string]$Script:WingetSourceCustom = 'winget'

# Defining custom repository for winget tool
if ($null -ne $Script:WAUConfig.WAU_WingetSourceCustom) {
    $Script:WingetSourceCustom = $Script:WAUConfig.WAU_WingetSourceCustom.Trim()
    Write-ToLog "Selecting winget repository named '$($Script:WingetSourceCustom)'"
}
#endregion WINGET SOURCE

#region Log running context
if ($true -eq $IsSystem) {

    # Maximum number of log files to keep. Default is 3. Setting MaxLogFiles to 0 will keep all log files.
    $MaxLogFiles = $WAUConfig.WAU_MaxLogFiles
    if ($null -eq $MaxLogFiles) {
        [int32]$MaxLogFiles = 3
    }
    else {
        [int32]$MaxLogFiles = $MaxLogFiles
    }

    # Maximum size of log file.
    $MaxLogSize = $WAUConfig.WAU_MaxLogSize
    if (!$MaxLogSize) {
        [int64]$MaxLogSize = [int64]1MB # in bytes, default is 1 MB = 1048576
    }
    else {
        [int64]$MaxLogSize = $MaxLogSize
    }

    #LogRotation if System
    [bool]$LogRotate = Invoke-LogRotation $LogFile $MaxLogFiles $MaxLogSize
    if ($false -eq $LogRotate) {
        Write-ToLog "An Exception occurred during Log Rotation..."
    }
}
#endregion Log running context

#region Run Scope Machine function if run as System
if ($true -eq $IsSystem) {
    Add-ScopeMachine
}
#endregion Run Scope Machine function if run as System

#region Get Notif Locale function
[string]$LocaleDisplayName = Get-NotifLocale
Write-ToLog "Notification Level: $($WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan"
#endregion Get Notif Locale function

#region MAIN
#Check network connectivity
if (Test-Network) {

    #Check prerequisites
    if ($true -eq $IsSystem) {
        Install-Prerequisites
    }

    #Check if Winget is installed and get Winget cmd
    [string]$Script:Winget = Get-WingetCmd
    Write-ToLog "Selected winget instance: $($Script:Winget)"

    if ($Script:Winget) {

        if ($true -eq $IsSystem) {

            #Get Current Version
            $WAUCurrentVersion = $WAUConfig.ProductVersion
            Write-ToLog "WAU current version: $WAUCurrentVersion"

            #Check if WAU update feature is enabled or not if run as System
            $WAUDisableAutoUpdate = $WAUConfig.WAU_DisableAutoUpdate
            #If yes then check WAU update if run as System
            if ($WAUDisableAutoUpdate -eq 1) {
                Write-ToLog "WAU AutoUpdate is Disabled." "Gray"
            }
            else {
                Write-ToLog "WAU AutoUpdate is Enabled." "Green"
                #Get Available Version
                $Script:WAUAvailableVersion = Get-WAUAvailableVersion
                #Compare
                if ((Compare-SemVer -Version1 $WAUCurrentVersion -Version2 $WAUAvailableVersion) -lt 0) {
                    #If new version is available, update it
                    Write-ToLog "WAU Available version: $WAUAvailableVersion" "DarkYellow"
                    Update-WAU
                }
                else {
                    Write-ToLog "WAU is up to date." "Green"
                }
            }

            #Delete previous list_/winget_error (if they exist) if run as System
            [string]$fp4 = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'error.txt')
            if (Test-Path $fp4) {
                Remove-Item $fp4 -Force
            }

            #Get External ListPath if run as System
            if ($WAUConfig.WAU_ListPath) {
                $ListPathClean = $($WAUConfig.WAU_ListPath.TrimEnd(" ", "\", "/"))
                Write-ToLog "WAU uses External Lists from: $ListPathClean"
                if ($ListPathClean -ne "GPO") {
                    $NewList = Test-ListPath $ListPathClean $WAUConfig.WAU_UseWhiteList $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                    if ($ReachNoPath) {
                        Write-ToLog "Couldn't reach/find/compare/copy from $ListPathClean..." "Red"
                        if ($ListPathClean -notlike "http*") {
                            if (Test-Path -Path "$ListPathClean" -PathType Leaf) {
                                Write-ToLog "PATH must end with a Directory, not a File..." "Red"
                            }
                        }
                        else {
                            if ($ListPathClean -match "_apps.txt") {
                                Write-ToLog "PATH must end with a Directory, not a File..." "Red"
                            }
                        }
                        $Script:ReachNoPath = $False
                    }
                    if ($NewList) {
                        if ($AlwaysDownloaded) {
                            Write-ToLog "List downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))" "DarkYellow"
                        }
                        else {
                            Write-ToLog "Newer List downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))" "DarkYellow"
                        }
                        $Script:AlwaysDownloaded = $False
                    }
                    else {
                        if ($WAUConfig.WAU_UseWhiteList -and (Test-Path "$WorkingDir\included_apps.txt")) {
                            Write-ToLog "List (white) is up to date." "Green"
                        }
                        elseif (!$WAUConfig.WAU_UseWhiteList -and (Test-Path "$WorkingDir\excluded_apps.txt")) {
                            Write-ToLog "List (black) is up to date." "Green"
                        }
                        else {
                            Write-ToLog "Critical: White/Black List doesn't exist, exiting..." "Red"
                            New-Item "$WorkingDir\logs\error.txt" -Value "White/Black List doesn't exist" -Force
                            Exit 1
                        }
                    }
                }
            }

            #Get External ModsPath if run as System
            if ($WAUConfig.WAU_ModsPath) {
                $ModsPathClean = $($WAUConfig.WAU_ModsPath.TrimEnd(" ", "\", "/"))
                Write-ToLog "WAU uses External Mods from: $ModsPathClean"
                if ($WAUConfig.WAU_AzureBlobSASURL) {
                    $NewMods, $DeletedMods = Test-ModsPath $ModsPathClean $WAUConfig.InstallLocation.TrimEnd(" ", "\") $WAUConfig.WAU_AzureBlobSASURL.TrimEnd(" ")
                }
                else {
                    $NewMods, $DeletedMods = Test-ModsPath $ModsPathClean $WAUConfig.InstallLocation.TrimEnd(" ", "\")
                }
                if ($ReachNoPath) {
                    Write-ToLog "Couldn't reach/find/compare/copy from $ModsPathClean..." "Red"
                    $Script:ReachNoPath = $False
                }
                if ($NewMods -gt 0) {
                    Write-ToLog "$NewMods newer Mods downloaded/copied to local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))\mods" "DarkYellow"
                }
                else {
                    if (Test-Path "$WorkingDir\mods\*.ps1") {
                        Write-ToLog "Mods are up to date." "Green"
                    }
                    else {
                        Write-ToLog "No Mods are implemented..." "DarkYellow"
                    }
                }
                if ($DeletedMods -gt 0) {
                    Write-ToLog "$DeletedMods Mods deleted (not externally managed) from local path: $($WAUConfig.InstallLocation.TrimEnd(" ", "\"))\mods" "Red"
                }
            }

            # Test if _WAU-mods.ps1 exist: Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM)
            $Mods = "$WorkingDir\mods"
            if (Test-Path "$Mods\_WAU-mods.ps1") {
                Write-ToLog "Running Mods for WAU..." "DarkYellow"
                Test-WAUMods -WorkingDir $WorkingDir -WAUConfig $WAUConfig -GitHub_Repo $GitHub_Repo
            }

        }

        #Get White or Black list
        if ($WAUConfig.WAU_UseWhiteList -eq 1) {
            Write-ToLog "WAU uses White List config"
            $toUpdate = Get-IncludedApps
            $UseWhiteList = $true
        }
        else {
            Write-ToLog "WAU uses Black List config"
            $toSkip = Get-ExcludedApps
        }

        #Get outdated Winget packages
        Write-ToLog "Checking application updates on Winget Repository named '$($Script:WingetSourceCustom)' .." "DarkYellow"
        $outdated = Get-WingetOutdatedApps -src $Script:WingetSourceCustom

        #If something unusual happened or no update found
        if ($outdated -like "No update found.*") {
            Write-ToLog "$outdated" "cyan"
        }
        #Run only if $outdated is populated!
        else {
            #Log list of app to update
            foreach ($app in $outdated) {
                #List available updates
                $Log = "-> Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
                $Log | Write-Host
                $Log | Out-File -FilePath $LogFile -Append
            }

            #Count good update installations
            $Script:InstallOK = 0

            #Trick under user context when -BypassListForUsers is used
            if ($IsSystem -eq $false -and $WAUConfig.WAU_BypassListForUsers -eq 1) {
                Write-ToLog "Bypass system list in user context is Enabled."
                $UseWhiteList = $false
                $toSkip = $null
            }

            #If White List
            if ($UseWhiteList) {
                #For each app, notify and update
                foreach ($app in $outdated) {
                    #if current app version is unknown, skip it
                    if ($($app.Version) -eq "Unknown") {
                        Write-ToLog "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
                    }
                    #if app is in "include list", update it
                    elseif ($toUpdate -contains $app.Id) {
                        Update-App $app
                    }
                    #if app with wildcard is in "include list", update it
                    elseif ($toUpdate | Where-Object { $app.Id -like $_ }) {
                        Write-ToLog "$($app.Name) is wildcard in the include list."
                        Update-App $app
                    }
                    #else, skip it
                    else {
                        Write-ToLog "$($app.Name) : Skipped upgrade because it is not in the included app list" "Gray"
                    }
                }
            }
            #If Black List or default
            else {
                #For each app, notify and update
                foreach ($app in $outdated) {
                    #if current app version is unknown, skip it
                    if ($($app.Version) -eq "Unknown") {
                        Write-ToLog "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
                    }
                    #if app is in "excluded list", skip it
                    elseif ($toSkip -contains $app.Id) {
                        Write-ToLog "$($app.Name) : Skipped upgrade because it is in the excluded app list" "Gray"
                    }
                    #if app with wildcard is in "excluded list", skip it
                    elseif ($toSkip | Where-Object { $app.Id -like $_ }) {
                        Write-ToLog "$($app.Name) : Skipped upgrade because it is *wildcard* in the excluded app list" "Gray"
                    }
                    # else, update it
                    else {
                        Update-App $app
                    }
                }
            }

            if ($InstallOK -gt 0) {
                Write-ToLog "$InstallOK apps updated ! No more update." "Green"
            }
        }

        if ($InstallOK -eq 0 -or !$InstallOK) {
            Write-ToLog "No new update." "Green"
        }

        # Test if _WAU-mods-postsys.ps1 exists: Mods for WAU (postsys) - if Network is active/any Winget is installed/running as SYSTEM _after_ SYSTEM updates
        if ($true -eq $IsSystem) {
            if (Test-Path "$Mods\_WAU-mods-postsys.ps1") {
                Write-ToLog "Running Mods (postsys) for WAU..." "DarkYellow"
                & "$Mods\_WAU-mods-postsys.ps1"
            }
        }

        #Check if user context is activated during system run
        if ($IsSystem -and ($WAUConfig.WAU_UserContext -eq 1)) {

            $UserContextTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -ErrorAction SilentlyContinue

            $explorerprocesses = @(Get-CimInstance -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
            If ($explorerprocesses.Count -eq 0) {
                Write-ToLog "No explorer process found / Nobody interactively logged on..."
            }
            Else {
                #Get Winget system apps to escape them before running user context
                Write-ToLog "User logged on, get a list of installed Winget apps in System context..."
                Get-WingetSystemApps -src $Script:WingetSourceCustom

                #Run user context scheduled task
                Write-ToLog "Starting WAU in User context..."
                $null = $UserContextTask | Start-ScheduledTask -ErrorAction SilentlyContinue
                Exit 0
            }
        }
    }
    else {
        Write-ToLog "Critical: Winget not installed or detected, exiting..." "red"
        New-Item "$WorkingDir\logs\error.txt" -Value "Winget not installed or detected" -Force
        Write-ToLog "End of process!" "Cyan"
        Exit 1
    }
}
#endregion MAIN

#End
Write-ToLog "End of process!" "Cyan"
Start-Sleep 3
