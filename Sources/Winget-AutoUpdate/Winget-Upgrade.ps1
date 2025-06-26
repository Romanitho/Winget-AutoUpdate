#region LOAD FUNCTIONS
# Get the Working Dir
[string]$Script:WorkingDir = $PSScriptRoot;

# Get Functions
Get-ChildItem -Path "$($Script:WorkingDir)\functions" -File -Filter "*.ps1" -Depth 0 | ForEach-Object { . $_.FullName; }
#endregion LOAD FUNCTIONS

<# MAIN #>

# Config console output encoding
$null = cmd /c '';
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;
$Script:ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue;

# Set GitHub Repo
[string]$Script:GitHub_Repo = "Winget-AutoUpdate";

# Log initialization
[string]$LogFile = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'updates.log');

#region Get settings and Domain/Local Policies (GPO) if activated.
Write-ToLog "Reading WAUConfig";
$Script:WAUConfig = Get-WAUConfig;

if ($WAUConfig.WAU_ActivateGPOManagement -eq 1) {
    Write-ToLog "WAU Policies management Enabled.";
}
#endregion Get settings and Domain/Local Policies (GPO) if activated.

# Default name of winget repository used within this script
[string]$DefaultWingetRepoName = 'winget';

#region Winget Source Custom
# Defining a custom source even if not used below (failsafe suggested by github/sebneus mentioned in issues/823)
[string]$Script:WingetSourceCustom = $DefaultWingetRepoName;

# Defining custom repository for winget tool (only if GPO management is active)
if ($Script:WAUConfig.WAU_ActivateGPOManagement) {
    if ($null -ne $Script:WAUConfig.WAU_WingetSourceCustom) {
        $Script:WingetSourceCustom = $Script:WAUConfig.WAU_WingetSourceCustom.Trim();
        Write-ToLog "Selecting winget repository named '$($Script:WingetSourceCustom)'";
    }
}
#endregion Winget Source Custom

#region Checking execution context
# Check if running account is system or interactive logon System(default) otherwise User
[bool]$Script:IsSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem;

# Check for current session ID (O = system without ServiceUI)
[Int32]$Script:SessionID = [System.Diagnostics.Process]::GetCurrentProcess().SessionId;
#endregion

# Preparation to run in current context
if ($true -eq $IsSystem) {

    #If log file doesn't exist, force create it
    if (!(Test-Path -Path $LogFile)) {
        Write-ToLog "New log file created";
    }

    # paths
    [string]$IntuneLogsDir = "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs";
    [string]$fp0 = [System.IO.Path]::Combine($IntuneLogsDir, 'WAU-updates.log');
    [string]$fp1 = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'install.log');
    [string]$fp2 = [System.IO.Path]::Combine($IntuneLogsDir, 'WAU-install.log');

    # Check if Intune Management Extension Logs folder exists
    if (Test-Path -Path $IntuneLogsDir -PathType Container -ErrorAction SilentlyContinue) {

        # Check if symlink WAU-updates.log exists, make symlink (doesn't work under ServiceUI)
        if (!(Test-Path -Path $fp0 -ErrorAction SilentlyContinue)) {
            New-Item -Path $fp0 -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue | Out-Null;
            Write-ToLog "SymLink for 'update' log file created in in $($IntuneLogsDir) folder";
        }

        # Check if install.log and symlink WAU-install.log exists, make symlink (doesn't work under ServiceUI)
        if ( (Test-Path -Path $fp1 -ErrorAction SilentlyContinue) -and !(Test-Path -Path $fp2 -ErrorAction SilentlyContinue) ) {
            New-Item -Path $fp2 -ItemType SymbolicLink -Value $fp1 -Force -Confirm:$False -ErrorAction SilentlyContinue | Out-Null;
            Write-ToLog "SymLink for 'install' log file created in $($IntuneLogsDir) folder"
        }
        # Check if user install.log and symlink WAU-install-username.log exists, make symlink (doesn't work under ServiceUI)
        # Get all user directories from C:\Users (excluding default/system profiles)
        $UserDirs = Get-ChildItem -Path "C:\Users" -Directory | Where-Object {
            ($_ -notmatch "Default") -and ($_ -notmatch "Public") -and ($_ -notmatch "All Users") -and ($_ -notmatch "Default User")
        }
        foreach ($UserDir in $UserDirs) {
            # Define user-specific log path and log file
            $UserLogPath = "$($UserDir.FullName)\AppData\Roaming\Winget-AutoUpdate\Logs"
            $UserLogFile = "$UserLogPath\install_$($UserDir.Name).log"

            # Check if the user's log file exists
            if (Test-Path -Path $UserLogFile -ErrorAction SilentlyContinue) {
                # Define the Symlink target
                $UserLogLink = "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-user_$($UserDir.Name).log"

                # Create Symlink if it doesn't already exist
                if (!(Test-Path -Path $UserLogLink -ErrorAction SilentlyContinue)) {
                    New-Item -Path $UserLogLink -ItemType SymbolicLink -Value $UserLogFile -Force -ErrorAction SilentlyContinue | Out-Null
                    Write-ToLog "Created Symlink for user log: $UserLogLink -> $UserLogFile"
                }
            }
        }
    }

    #Check if running with session ID 0
    if ($SessionID -eq 0) {
        #Check if ServiceUI exists
        [string]$fp3 = [System.IO.Path]::Combine($Script:WorkingDir, 'ServiceUI.exe');
        [bool]$ServiceUI = Test-Path $fp3 -PathType Leaf;
        if ($true -eq $ServiceUI) {
            #Check if any connected user
            $explorerprocesses = @(Get-CimInstance -Query "SELECT * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue);
            if ($explorerprocesses.Count -gt 0) {
                Write-ToLog "Rerun WAU in system context with ServiceUI";
                Start-Process `
                    -FilePath $fp3 `
                    -ArgumentList "-process:explorer.exe $env:windir\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File winget-upgrade.ps1" `
                    -WorkingDirectory $WorkingDir;
                Wait-Process "ServiceUI" -ErrorAction SilentlyContinue;
                Exit 0;
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

#region Log running context
if ($true -eq $IsSystem) {

    # Maximum number of log files to keep. Default is 3. Setting MaxLogFiles to 0 will keep all log files.
    $MaxLogFiles = $WAUConfig.WAU_MaxLogFiles
    if ($null -eq $MaxLogFiles) {
        [int32]$MaxLogFiles = 3;
    }
    else {
        [int32]$MaxLogFiles = $MaxLogFiles;
    }

    # Maximum size of log file.
    $MaxLogSize = $WAUConfig.WAU_MaxLogSize;
    if (!$MaxLogSize) {
        [int64]$MaxLogSize = [int64]1MB; # in bytes, default is 1 MB = 1048576
    }
    else {
        [int64]$MaxLogSize = $MaxLogSize;
    }

    #LogRotation if System
    [bool]$LogRotate = Invoke-LogRotation $LogFile $MaxLogFiles $MaxLogSize;
    if ($false -eq $LogRotate) {
        Write-ToLog "An Exception occurred during Log Rotation..."
    }
}
#endregion Log running context

#region Run Scope Machine function if run as System
if ($true -eq $IsSystem) {
    Add-ScopeMachine;
}
#endregion Run Scope Machine function if run as System

#region Get Notif Locale function
[string]$LocaleDisplayName = Get-NotifLocale;
Write-ToLog "Notification Level: $($WAUConfig.WAU_NotificationLevel). Notification Language: $LocaleDisplayName" "Cyan";
#endregion

#Check network connectivity
if (Test-Network) {

    #Check prerequisites
    if ($true -eq $IsSystem) {
        Install-Prerequisites;
    }

    #Check if Winget is installed and get Winget cmd
    [string]$Script:Winget = Get-WingetCmd;
    Write-ToLog "Selected winget instance: $($Script:Winget)";

    if ($Script:Winget) {

        if ($true -eq $IsSystem) {

            #Get Current Version
            $WAUCurrentVersion = $WAUConfig.ProductVersion;
            Write-ToLog "WAU current version: $WAUCurrentVersion";

            #Check if WAU update feature is enabled or not if run as System
            $WAUDisableAutoUpdate = $WAUConfig.WAU_DisableAutoUpdate;
            #If yes then check WAU update if run as System
            if ($WAUDisableAutoUpdate -eq 1) {
                Write-ToLog "WAU AutoUpdate is Disabled." "Gray";
            }
            else {
                Write-ToLog "WAU AutoUpdate is Enabled." "Green";
                #Get Available Version
                $Script:WAUAvailableVersion = Get-WAUAvailableVersion;
                #Compare
                if ((Compare-SemVer -Version1 $WAUCurrentVersion -Version2 $WAUAvailableVersion) -lt 0) {
                    #If new version is available, update it
                    Write-ToLog "WAU Available version: $WAUAvailableVersion" "DarkYellow";
                    Update-WAU;
                }
                else {
                    Write-ToLog "WAU is up to date." "Green";
                }
            }

            #Delete previous list_/winget_error (if they exist) if run as System
            [string]$fp4 = [System.IO.Path]::Combine($Script:WorkingDir, 'logs', 'error.txt');
            if (Test-Path $fp4) {
                Remove-Item $fp4 -Force;
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

            #Test if _WAU-mods.ps1 exist: Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM)
            $Mods = "$WorkingDir\mods"
            if (Test-Path "$Mods\_WAU-mods.ps1") {
                Write-ToLog "Running Mods for WAU..." "Cyan"

                # Capture both output and exit code
                $ModsOutput = & "$Mods\_WAU-mods.ps1" 2>&1 | Out-String
                $ModsExitCode = $LASTEXITCODE

                # Handle legacy exit code behavior first (backward compatibility)
                if ($ModsExitCode -eq 1) {
                    Write-ToLog "Legacy exit code 1 detected - Re-running WAU"
                    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade.ps1`""
                    Exit
                }

                # Try to parse JSON output for new action-based system
                if ($ModsOutput -and $ModsOutput.Trim()) {
                    try {
                        # Remove any non-JSON content (like debug output) and find JSON
                        $jsonMatch = $ModsOutput | Select-String -Pattern '\{.*\}' | Select-Object -First 1
                        
                        if ($jsonMatch) {
                            $ModsResult = $jsonMatch.Matches[0].Value | ConvertFrom-Json
                            
                            # Log message if provided
                            if ($ModsResult.Message) {
                                $logLevel = if ($ModsResult.LogLevel) { $ModsResult.LogLevel } else { "White" }
                                Write-ToLog $ModsResult.Message $logLevel
                            }
                            
                            # Execute action based on returned instruction
                            switch ($ModsResult.Action) {
                                "Rerun" {
                                    Write-ToLog "Mods requested a WAU re-run"
                                    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade.ps1`""
                                    $exitCode = if ($ModsResult.ExitCode) { [int]$ModsResult.ExitCode } else { 0 }
                                    Exit $exitCode
                                }
                                "Abort" {
                                    Write-ToLog "Mods requested WAU to abort"
                                    $exitCode = if ($ModsResult.ExitCode) { [int]$ModsResult.ExitCode } else { 1602 }  # Default to "User cancelled"
                                    Exit $exitCode
                                }
                                "Postpone" {
                                    Write-ToLog "Mods requested a postpone of WAU"
                                    # Check if a postponed task already exists
                                    $existingTask = Get-ScheduledTask -TaskPath "\WAU\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "Postponed-$($Script:GitHub_Repo)*" }
                                    if ($existingTask) {
                                        Write-ToLog "A postponed task for $($Script:GitHub_Repo) already exists, not creating another." "Yellow"
                                    }
                                    else {
                                        # Get configurable duration, default to 1 hour
                                        $postponeDuration = if ($ModsResult.PostponeDuration) {
                                            try {
                                                [double]$parsedDuration = [double]$ModsResult.PostponeDuration
                                                # Ensure minimum duration of 0.1 hours (6 minutes)
                                                if ($parsedDuration -lt 0.1) {
                                                    Write-ToLog "PostponeDuration adjusted to minimum 0.1 hours (6 minutes)" "Yellow"
                                                    0.1
                                                } else {
                                                    $parsedDuration
                                                }
                                            }
                                            catch {
                                                Write-ToLog "Invalid PostponeDuration value '$($ModsResult.PostponeDuration)', using default 1 hour" "Yellow"
                                                1
                                            }
                                        } else {
                                            1
                                        }

                                        # Create a postponed temporary scheduled task to try again later
                                        $uniqueTaskName = "Postponed-$($Script:GitHub_Repo)_$(Get-Random)"
                                        $taskPath = "\WAU\"
                                        $copyAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WAUConfig.InstallLocation)Winget-Upgrade.ps1`""
                                        $copyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours($postponeDuration)
                                        # Set EndBoundary to make DeleteExpiredTaskAfter work
                                        $copyTrigger.EndBoundary = (Get-Date).AddHours($postponeDuration).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss")
                                        $copySettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 0)
                                        $copyPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                                        Register-ScheduledTask -TaskName $uniqueTaskName -TaskPath $taskPath -Action $copyAction -Trigger $copyTrigger -Settings $copySettings -Principal $copyPrincipal -Description "Postponed copy of $Script:GitHub_Repo" | Out-Null
                                        Write-ToLog "WAU will try again in $postponeDuration hours" "Yellow"
                                    }
                                    $exitCode = if ($ModsResult.ExitCode) { [int]$ModsResult.ExitCode } else { 1602 }  # Default to "User cancelled"
                                    Exit $exitCode
                                }
                                "Reboot" {
                                    Write-ToLog "Mods requested a system reboot"
                                    # Get configurable delay, default to 5 minutes
                                    $rebootDelay = if ($ModsResult.RebootDelay) {
                                        try {
                                            [double]$parsedDelay = [double]$ModsResult.RebootDelay
                                            # Ensure minimum delay of 1 minute for safety
                                            if ($parsedDelay -lt 1) {
                                                Write-ToLog "RebootDelay adjusted to minimum 1 minute" "Yellow"
                                                1
                                            } else {
                                                $parsedDelay
                                            }
                                        }
                                        catch {
                                            Write-ToLog "Invalid RebootDelay value '$($ModsResult.RebootDelay)', using default 5 minutes" "Yellow"
                                            5
                                        }
                                    } else {
                                        5
                                    }

                                    $shutdownMessage = if ($ModsResult.Message) { $ModsResult.Message } else { "WAU Mods requested a system reboot in $rebootDelay minutes" }
                                    
                                    # Check if SCCM client is available for managed restart (user controlled)
                                    $sccmClient = Get-CimInstance -Namespace "root\ccm" -ClassName "SMS_Client" -ErrorAction SilentlyContinue
                                    
                                    if ($sccmClient) {
                                        Write-ToLog "SCCM client detected - using managed restart (user controlled)" "Green"

                                        try {
                                            $ccmRestartPath = "$env:windir\CCM\CcmRestart.exe"
                                            $regPath = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData'
                                            
                                            # Check if SCCM restart registry values already exist
                                            $existingRebootBy = $null
                                            $existingRebootValues = $false
                                            
                                            if (Test-Path $regPath) {
                                                $existingRebootBy = Get-ItemProperty -Path $regPath -Name 'RebootBy' -ErrorAction SilentlyContinue
                                                $existingNotifyUI = Get-ItemProperty -Path $regPath -Name 'NotifyUI' -ErrorAction SilentlyContinue
                                                $existingSetTime = Get-ItemProperty -Path $regPath -Name 'SetTime' -ErrorAction SilentlyContinue
                                                
                                                # Check if we have the key registry values indicating a restart is already scheduled
                                                if ($existingRebootBy -and $existingNotifyUI -and $existingSetTime -and $existingRebootBy.PSObject.Properties['RebootBy']) {
                                                    $existingRebootValues = $true
                                                    $existingRestartTime = [DateTimeOffset]::FromUnixTimeSeconds([int64]$existingRebootBy.RebootBy).LocalDateTime
                                                    Write-ToLog "SCCM restart already scheduled for: $existingRestartTime" "Yellow"
                                                }
                                            }
                                            
                                            if ($existingRebootValues) {
                                                # Try CcmRestart.exe for notification
                                                if (Test-Path $ccmRestartPath) {
                                                    Write-ToLog "Triggering SCCM restart notification via CcmRestart.exe" "Cyan"
                                                    Start-Process -FilePath $ccmRestartPath -NoNewWindow -Wait -ErrorAction SilentlyContinue
                                                } else {
                                                    Write-ToLog "CcmRestart.exe not found, restarting ccmexec service" "Yellow"
                                                    Restart-Service ccmexec -Force -ErrorAction SilentlyContinue
                                                }
                                            } else {
                                                # No existing restart scheduled - create new SCCM managed restart (user controlled)
                                                Write-ToLog "Setting up new SCCM managed restart schedule" "Green"
                                                
                                                # Check the intended exit code to determine restart type
                                                $intendedExitCode = if ($ModsResult.ExitCode) { $ModsResult.ExitCode } else { 3010 }
                                                $hardRebootValue = if ($intendedExitCode -eq 1641) { 1 } else { 0 }
                                                
                                                
                                                if ($intendedExitCode -eq 1641) {
                                                    Write-ToLog "Exit code 1641 detected - using hard reboot for SCCM restart" "Yellow"
                                                } else {
                                                    Write-ToLog "Using soft reboot for SCCM restart (exit code: $intendedExitCode)" "Cyan"
                                                }
                                                
                                                $restartTime = [DateTimeOffset]::Now.AddMinutes($rebootDelay).ToUnixTimeSeconds()
                                                
                                                # Ensure registry path exists
                                                if (-not (Test-Path $regPath)) {
                                                    New-Item -Path $regPath -Force | Out-Null
                                                }
                                                
                                                # Set restart properties for SCCM
                                                New-ItemProperty -Path $regPath -Name 'RebootBy' -Value ([Int64]$restartTime) -PropertyType QWord -Force | Out-Null
                                                New-ItemProperty -Path $regPath -Name 'RebootValueInUTC' -Value 1 -PropertyType DWord -Force | Out-Null
                                                New-ItemProperty -Path $regPath -Name 'NotifyUI' -Value 1 -PropertyType DWord -Force | Out-Null
                                                New-ItemProperty -Path $regPath -Name 'HardReboot' -Value $hardRebootValue -PropertyType DWord -Force | Out-Null
                                                New-ItemProperty -Path $regPath -Name 'SetTime' -Value 1 -PropertyType DWord -Force | Out-Null
                                                
                                                # Try CcmRestart.exe first for notification
                                                if (Test-Path $ccmRestartPath) {
                                                    Write-ToLog "Triggering SCCM restart notification via CcmRestart.exe" "Cyan"
                                                    Start-Process -FilePath $ccmRestartPath -NoNewWindow -Wait -ErrorAction SilentlyContinue
                                                } else {
                                                    Write-ToLog "CcmRestart.exe not found, restarting ccmexec service" "Yellow"
                                                    Restart-Service ccmexec -Force -ErrorAction SilentlyContinue
                                                }
                                                
                                                Write-ToLog "SCCM managed restart scheduled for: $([DateTimeOffset]::FromUnixTimeSeconds($restartTime).LocalDateTime)" "Green"
                                            }
                                        }
                                        catch {
                                            Write-ToLog "Failed to set SCCM restart: $($_.Exception.Message). Falling back to standard restart." "Yellow"
                                            # Fallback to standard shutdown
                                            $result = & shutdown /r /t ([int]($rebootDelay * 60)) /c $shutdownMessage 2>&1
                                            if ($LASTEXITCODE -eq 0) {
                                                Write-ToLog "System restart scheduled in $rebootDelay minutes (fallback)" "Yellow"
                                            } else {
                                                Write-ToLog "A system shutdown has already been scheduled or failed: $result" "Yellow"
                                            }
                                        }
                                    } else {
                                        # Standard shutdown when SCCM is not available
                                        $result = & shutdown /r /t ([int]($rebootDelay * 60)) /c $shutdownMessage 2>&1
                                        if ($LASTEXITCODE -eq 0) {
                                            Write-ToLog "System restart scheduled in $rebootDelay minutes" "Yellow"
                                        } else {
                                            Write-ToLog "A system shutdown has already been scheduled or failed: $result" "Yellow"
                                        }
                                    }
                                    $exitCode = if ($ModsResult.ExitCode) { [int]$ModsResult.ExitCode } else { 3010 }  # Default to "Restart required"
                                    Exit $exitCode
                                }
                                "Continue" {
                                    Write-ToLog "Mods allows WAU to continue normally"
                                }
                                default {
                                    Write-ToLog "Unknown action '$($ModsResult.Action)' from mods, continuing normally" "Cyan"
                                }
                            }
                        }
                    }
                    catch {
                        Write-ToLog "Failed to parse mods JSON output: $($_.Exception.Message)" "Red"
                        Write-ToLog "Continuing with normal WAU execution" "Cyan"
                    }
                }
            }

        }

        if ($($WAUConfig.WAU_ListPath) -eq "GPO") {
            $Script:GPOList = $True
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

        #Fix and count the array if GPO List as ERROR handling!
        if ($GPOList) {
            if ($UseWhiteList) {
                if (-not $toUpdate) {
                    Write-ToLog "Critical: Whitelist doesn't exist in GPO, exiting..." "Red"
                    New-Item "$WorkingDir\logs\error.txt" -Value "Whitelist doesn't exist in GPO" -Force
                    Exit 1
                }
                foreach ($app in $toUpdate) { Write-ToLog "Include app ${app}" }
            }
            else {
                if (-not $toSkip) {
                    Write-ToLog "Critical: Blacklist doesn't exist in GPO, exiting..." "Red"
                    New-Item "$WorkingDir\logs\error.txt" -Value "Blacklist doesn't exist in GPO" -Force
                    Exit 1
                }
                foreach ($app in $toSkip) { Write-ToLog "Exclude app ${app}" }
            }
        }

        #Get outdated Winget packages
        Write-ToLog "Checking application updates on Winget Repository named '$($Script:WingetSourceCustom)' .." "DarkYellow"
        $outdated = Get-WingetOutdatedApps -src $Script:WingetSourceCustom;

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

        #Test if _WAU-mods-postsys.ps1 exists: Mods for WAU (postsys) - if Network is active/any Winget is installed/running as SYSTEM _after_ SYSTEM updates
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
                Get-WingetSystemApps -src $Script:WingetSourceCustom;

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

#End
Write-ToLog "End of process!" "Cyan"
Start-Sleep 3
