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

        #region USER-CONTEXT UPDATE REQUEST
        # When WAU-UpdateNow encounters user-scoped apps, it writes
        # user-context-update.json and triggers the UserContext task.
        # If that file exists, process those updates and exit.
        if (-not $Script:IsSystem) {
            $userUpdateJson = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'user-context-update.json')
            if (Test-Path $userUpdateJson) {
                $Script:InstallOK = 0
                Write-ToLog "Processing user-context updates triggered by UpdateNow" "Cyan"
                try {
                    $userApps = @(Get-Content -Path $userUpdateJson -Raw -Encoding UTF8 | ConvertFrom-Json)
                }
                catch {
                    Write-ToLog "ERROR: Could not parse user-context-update.json" "Red"
                    Remove-Item -Path $userUpdateJson -Force -ErrorAction SilentlyContinue
                    Exit 1
                }
                # Track per-app success via $Script:InstallOK delta so that only
                # confirmed-updated apps are dropped from user-context-outdated.csv.
                # Update-App already calls Confirm-Installation and increments
                # $Script:InstallOK on success -- no need to re-confirm here.
                $updatedIds = [System.Collections.Generic.List[string]]::new()
                foreach ($app in $userApps) {
                    Write-ToLog "-> $($app.Name) : $($app.Version) -> $($app.AvailableVersion)"
                    $before = $Script:InstallOK
                    Update-App $app -src $Script:WingetSourceCustom
                    if ($Script:InstallOK -gt $before) {
                        $updatedIds.Add($app.Id)
                    }
                }
                try {
                    Remove-Item -Path $userUpdateJson -Force -ErrorAction Stop
                }
                catch {
                    Write-ToLog "WARNING: Could not delete user-context-update.json -- $($_.Exception.Message)" "Yellow"
                }
                if ($Script:InstallOK -gt 0) {
                    Write-ToLog "$Script:InstallOK user-context apps updated" "Green"
                }

                # Remove only successfully-updated apps from user-context-outdated.csv.
                # Failed updates stay in the CSV so the next SYSTEM cycle re-merges
                # them into deadline tracking and their FirstDetected/Deadline
                # registry entries are preserved (no clock reset on failure).
                # Deleting the entire file would purge deadline entries for apps
                # that weren't updated (they wouldn't be in $deadlineApps).
                $userOutdatedPath = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'user-context-outdated.csv')
                if (Test-Path $userOutdatedPath) {
                    if ($updatedIds.Count -eq 0) {
                        Write-ToLog "No user-context apps successfully updated; user-context-outdated.csv unchanged" "Yellow"
                    }
                    else {
                        $remaining = @(Import-Csv -Path $userOutdatedPath -Encoding UTF8 |
                            Where-Object { $_.Id -notin $updatedIds })
                        if ($remaining.Count -gt 0) {
                            $remaining | Export-Csv -Path $userOutdatedPath -NoTypeInformation -Encoding UTF8 -Force
                            Write-ToLog "Removed $($updatedIds.Count) updated apps from user-context-outdated.csv ($($remaining.Count) remaining)"
                        }
                        else {
                            Remove-Item -Path $userOutdatedPath -Force -ErrorAction SilentlyContinue
                            Write-ToLog "Cleared user-context-outdated.csv (all apps updated)"
                        }
                    }
                }

                Write-ToLog "End of user-context update process" "Cyan"
                Start-Sleep 3
                Exit 0
            }
        }
        #endregion USER-CONTEXT UPDATE REQUEST

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

        #region DEADLINE CONFIG
        # Read update deadline settings. Both contexts need to know if deadline mode
        # is active: SYSTEM manages deadlines, user context detects user-scoped apps.
        # DeadlineDays = 0 means deadline mode is disabled -- normal silent update behaviour applies.
        [int]$DeadlineDays = 0
        [int]$ReminderIntervalDays = 2
        if ($null -ne $WAUConfig.WAU_UpdateDeadlineDays) {
            try { $DeadlineDays = [int]$WAUConfig.WAU_UpdateDeadlineDays } catch {}
        }
        if ($null -ne $WAUConfig.WAU_ReminderIntervalDays) {
            try { $ReminderIntervalDays = [int]$WAUConfig.WAU_ReminderIntervalDays } catch {}
        }
        if ($Script:IsSystem -and $DeadlineDays -le 0) {
            # When deadline mode is disabled, purge any leftover registry entries so that
            # re-enabling deadline mode later does not treat old entries as instantly overdue.
            $DeadlineRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines"
            if (Test-Path $DeadlineRegPath) {
                Remove-Item -Path $DeadlineRegPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToLog "Deadline mode disabled -- registry entries purged"
            }
        }
        # Ensure ProgramData shared directory exists and is writable by user context.
        # SYSTEM creates the directory with Modify permission for Authenticated Users
        # so that user context can create, overwrite, and delete JSON files there.
        if ($Script:IsSystem -and $DeadlineDays -gt 0 -and $WAUConfig.WAU_UserContext -eq 1) {
            $sharedDir = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate')
            if (-not (Test-Path $sharedDir)) {
                New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null
            }
            try {
                $acl = Get-Acl $sharedDir
                $authUsersSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')
                $authUsersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $authUsersSid, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $hasModifyForAuthUsers = $false
                foreach ($ace in $acl.Access) {
                    try {
                        $aceSid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
                    }
                    catch { continue }
                    if ($aceSid -eq $authUsersSid -and
                        ($ace.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify)) {
                        $hasModifyForAuthUsers = $true
                        break
                    }
                }
                if (-not $hasModifyForAuthUsers) {
                    $acl.SetAccessRule($authUsersRule)
                    Set-Acl $sharedDir $acl
                }
            }
            catch {
                Write-ToLog "Could not set ACL on shared directory: $($_.Exception.Message)" "Yellow"
            }
        }
        #endregion DEADLINE CONFIG

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

            #region DEADLINE MODE
            # In user context, skip all updates when deadline mode is active --
            # the SYSTEM task manages updates via the deadline prompt workflow.
            if ($DeadlineDays -gt 0 -and -not $Script:IsSystem) {
                # User context + deadline mode: detect outdated apps and save for
                # SYSTEM to merge into deadline tracking on its next run.
                if ($UseWhiteList) {
                    $userEligible = @($outdated | Where-Object {
                        $id = $_.Id
                        ($toUpdate -contains $id) -or ($toUpdate | Where-Object { $id -like $_ })
                    })
                }
                else {
                    $userEligible = @($outdated | Where-Object {
                        $id = $_.Id
                        -not ($toSkip -contains $id) -and -not ($toSkip | Where-Object { $id -like $_ })
                    })
                }

                $userOutdatedDir = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate')
                if (-not (Test-Path $userOutdatedDir)) { New-Item -ItemType Directory -Path $userOutdatedDir -Force | Out-Null }
                $userOutdatedPath = [System.IO.Path]::Combine($userOutdatedDir, 'user-context-outdated.csv')
                # Clean up old JSON format if present (migrated to CSV)
                $oldJsonPath = [System.IO.Path]::Combine($userOutdatedDir, 'user-context-outdated.json')
                if (Test-Path $oldJsonPath) { Remove-Item -Path $oldJsonPath -Force -ErrorAction SilentlyContinue }
                if ($userEligible.Count -gt 0) {
                    try {
                        $userEligible | Select-Object Name, Id, Version, AvailableVersion |
                            Export-Csv -Path $userOutdatedPath -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop
                        Write-ToLog "$($userEligible.Count) user-context outdated apps written for deadline tracking" "Cyan"
                    }
                    catch {
                        Write-ToLog "Failed to write user-context-outdated.csv: $($_.Exception.Message)" "Red"
                    }
                }
                else {
                    if (Test-Path $userOutdatedPath) {
                        Remove-Item -Path $userOutdatedPath -Force -ErrorAction SilentlyContinue
                    }
                    Write-ToLog "No user-context apps eligible for deadline tracking" "Gray"
                }
            }
            elseif ($DeadlineDays -gt 0 -and $Script:IsSystem) {

                Write-ToLog "Deadline mode active - $DeadlineDays days to forced update" "Cyan"

                # Filter outdated apps through whitelist/blacklist before deadline processing.
                # Without this, excluded apps (e.g. WAU itself) would get deadline-tracked.
                if ($UseWhiteList) {
                    $deadlineApps = @($outdated | Where-Object {
                        $id = $_.Id
                        ($toUpdate -contains $id) -or ($toUpdate | Where-Object { $id -like $_ })
                    })
                    $skippedCount = @($outdated).Count - $deadlineApps.Count
                    if ($skippedCount -gt 0) {
                        Write-ToLog "$skippedCount apps excluded from deadline tracking (not in whitelist)" "Gray"
                    }
                }
                else {
                    $deadlineApps = @($outdated | Where-Object {
                        $id = $_.Id
                        -not ($toSkip -contains $id) -and -not ($toSkip | Where-Object { $id -like $_ })
                    })
                    $skippedCount = @($outdated).Count - $deadlineApps.Count
                    if ($skippedCount -gt 0) {
                        Write-ToLog "$skippedCount apps excluded from deadline tracking (in blacklist)" "Gray"
                    }
                }

                # Merge user-context outdated apps if UserContext is enabled.
                # The CSV file is written by the user-context run on the previous cycle.
                # CSV is used instead of JSON to avoid PS 5.1 ConvertFrom-Json
                # serialization artifacts that corrupt object properties on round-trip.
                if ($WAUConfig.WAU_UserContext -eq 1) {
                    $userOutdatedPath = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'user-context-outdated.csv')
                    if (Test-Path $userOutdatedPath) {
                        try {
                            $userContextApps = @(Import-Csv -Path $userOutdatedPath -Encoding UTF8)
                            foreach ($uApp in $userContextApps) {
                                if (-not $uApp.Id) { continue }
                                if (-not ($deadlineApps | Where-Object { $_.Id -eq $uApp.Id })) {
                                    $uApp | Add-Member -NotePropertyName 'Scope' -NotePropertyValue 'user' -Force
                                    $deadlineApps += $uApp
                                }
                            }
                            Write-ToLog "$($userContextApps.Count) user-context apps merged for deadline tracking"
                        }
                        catch {
                            Write-ToLog "WARNING: Could not read user-context-outdated.csv -- $($_.Exception.Message)" "Yellow"
                        }
                    }
                }

                # Tag machine-scope apps
                foreach ($mApp in $deadlineApps) {
                    if (-not ($mApp.PSObject.Properties.Name -contains 'Scope')) {
                        $mApp | Add-Member -NotePropertyName 'Scope' -NotePropertyValue 'machine' -Force
                    }
                }

                # Step 1: Sync deadline registry.
                # First call with -OutdatedApps purges entries for apps no longer outdated
                # (e.g. user self-updated outside WAU). Second call refreshes our working list.
                $null = Get-UpdateDeadlines -OutdatedApps $deadlineApps
                foreach ($app in $deadlineApps) {
                    Set-UpdateDeadline -App $app -DeadlineDays $DeadlineDays
                }
                $deadlines = Get-UpdateDeadlines

                # Step 2: Split into overdue (past deadline) and pending (deadline not yet reached).
                $today = (Get-Date).Date
                $overdueEntries = @($deadlines | Where-Object { $_.Deadline.Date -lt $today })
                $pendingEntries = @($deadlines | Where-Object { $_.Deadline.Date -ge $today })

                # User-scoped overdue apps cannot be force-updated by SYSTEM.
                # Move them to pending so they appear in the prompt instead.
                $overdueUserIds = @($overdueEntries | ForEach-Object {
                    $appId = $_.AppId
                    $app = $deadlineApps | Where-Object { $_.Id -eq $appId } | Select-Object -First 1
                    if ($app -and $app.Scope -eq 'user') { $appId }
                })
                if ($overdueUserIds.Count -gt 0) {
                    $pendingEntries = @($pendingEntries) + @($overdueEntries | Where-Object { $_.AppId -in $overdueUserIds })
                    $overdueEntries = @($overdueEntries | Where-Object { $_.AppId -notin $overdueUserIds })
                    Write-ToLog "$($overdueUserIds.Count) overdue user-scoped apps moved to prompt" "DarkYellow"
                }

                Write-ToLog "Deadline summary: $($overdueEntries.Count) overdue (machine), $($pendingEntries.Count) pending"

                # Step 3: Forced background update for overdue apps -- no dialog shown.
                if ($overdueEntries.Count -gt 0) {
                    Write-ToLog "Processing $($overdueEntries.Count) overdue apps" "DarkYellow"
                    foreach ($entry in $overdueEntries) {
                        $app = $deadlineApps | Where-Object { $_.Id -eq $entry.AppId } | Select-Object -First 1
                        if ($app -and $app.Version -ne "Unknown") {
                            Write-ToLog "Forced update (deadline reached): $($app.Name)"
                            Update-App $app -src $Script:WingetSourceCustom
                            if (Confirm-Installation $app.Id $app.AvailableVersion $Script:WingetSourceCustom) {
                                $DeadlineAppRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\UpdateDeadlines\$($app.Id)"
                                if (Test-Path $DeadlineAppRegPath) {
                                    Remove-Item -Path $DeadlineAppRegPath -Recurse -Force -ErrorAction SilentlyContinue
                                    Write-ToLog "Deadline entry purged (update confirmed): $($app.Id)"
                                }
                            }
                            else {
                                Write-ToLog "$($app.Name) : forced update could not be confirmed -- deadline entry preserved" "Yellow"
                            }
                        }
                        elseif ($app -and $app.Version -eq "Unknown") {
                            Write-ToLog "$($app.Name) : Skipped forced update because current version is 'Unknown'" "Gray"
                        }
                    }
                }

                # Step 4: Show deadline prompt for pending apps if a user is logged in and
                # the snooze window has expired.
                if ($pendingEntries.Count -gt 0) {
                    $explorerprocesses = @(Get-CimInstance -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
                    if ($explorerprocesses.Count -eq 0) {
                        Write-ToLog "No user logged on -- skipping update prompt for $($pendingEntries.Count) pending apps" "Gray"
                    }
                    else {
                        # Check snooze: if NextPromptTime is set and hasn't elapsed, skip the prompt.
                        $showPrompt = $true
                        try {
                            $WAURegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate'
                            $nptStr = (Get-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -ErrorAction SilentlyContinue).NextPromptTime
                            if ($nptStr) {
                                $npt = [DateTime]::Parse($nptStr)
                                if ((Get-Date) -lt $npt) {
                                    $showPrompt = $false
                                    Write-ToLog "Update prompt snoozed until $($npt.ToString('g'))" "Gray"
                                }
                            }
                        }
                        catch {
                            # Parse failure -- show the prompt (fail open)
                        }

                        if ($showPrompt) {
                            # Build the pending apps payload, enriching each deadline entry with
                            # live name/version data from the current winget outdated list.
                            $promptApps = @(foreach ($entry in $pendingEntries) {
                                $app = $deadlineApps | Where-Object { $_.Id -eq $entry.AppId } | Select-Object -First 1
                                if ($app) {
                                    [PSCustomObject]@{
                                        Name             = $app.Name
                                        Id               = $app.Id
                                        Version          = $app.Version
                                        AvailableVersion = $entry.AvailableVersion
                                        Deadline         = $entry.Deadline.ToString('yyyy-MM-dd')
                                        Scope            = if ($app.Scope) { $app.Scope } else { 'machine' }
                                    }
                                }
                            })

                            if ($promptApps.Count -gt 0) {
                                $companyName = if ($WAUConfig.WAU_CompanyName) { $WAUConfig.WAU_CompanyName } else { '' }
                                Start-UpdatePromptTask -PendingApps $promptApps -ReminderIntervalDays $ReminderIntervalDays -CompanyName $companyName
                                Write-ToLog "Update prompt fired for $($promptApps.Count) apps"
                            }
                        }
                    }
                }

            }
            #endregion DEADLINE MODE
            else {

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
                            Update-App $app -src $Script:WingetSourceCustom
                        }
                        #if app with wildcard is in "include list", update it
                        elseif ($toUpdate | Where-Object { $app.Id -like $_ }) {
                            Write-ToLog "$($app.Name) is wildcard in the include list."
                            Update-App $app -src $Script:WingetSourceCustom
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
                            Update-App $app -src $Script:WingetSourceCustom
                        }
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
