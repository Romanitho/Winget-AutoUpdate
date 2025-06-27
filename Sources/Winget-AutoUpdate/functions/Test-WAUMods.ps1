function Test-WAUMods {
    param (
        [Parameter(Mandatory=$true)]
        [string]$WorkingDir,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$WAUConfig,

        [Parameter(Mandatory=$false)]
        [string]$GitHub_Repo = "Winget-AutoUpdate"
    )

    # Define Mods path
    $Mods = "$WorkingDir\mods"

    # Capture both output and exit code
    $ModsOutput = & "$Mods\_WAU-mods.ps1" 2>&1 | Out-String
    $ModsExitCode = $LASTEXITCODE

    # Handle legacy exit code behavior first (backward compatibility)
    if ($ModsExitCode -eq 1) {
        Write-ToLog "Legacy exit code 1 detected - Re-running WAU"
        Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\Winget-Upgrade.ps1`""
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
                        Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$WorkingDir\Winget-Upgrade.ps1`""
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
                        $existingTask = Get-ScheduledTask -TaskPath "\WAU\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "Postponed-$($GitHub_Repo)*" }
                        if ($existingTask) {
                            Write-ToLog "A postponed task for $($GitHub_Repo) already exists, not creating another." "Yellow"
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
                            $uniqueTaskName = "Postponed-$($GitHub_Repo)_$(Get-Random)"
                            $taskPath = "\WAU\"
                            $copyAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WAUConfig.InstallLocation)Winget-Upgrade.ps1`""
                            $copyTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours($postponeDuration)
                            # Set EndBoundary to make DeleteExpiredTaskAfter work
                            $copyTrigger.EndBoundary = (Get-Date).AddHours($postponeDuration).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss")
                            $copySettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 0)
                            $copyPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                            Register-ScheduledTask -TaskName $uniqueTaskName -TaskPath $taskPath -Action $copyAction -Trigger $copyTrigger -Settings $copySettings -Principal $copyPrincipal -Description "Postponed copy of $($GitHub_Repo)" | Out-Null
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
                        $rebootHandler = if ($ModsResult.RebootHandler) { $ModsResult.RebootHandler } else { "Windows" }
                        
                        # Check if SCCM client is available for managed restart (user controlled)
                        $sccmClient = Get-CimInstance -Namespace "root\ccm" -ClassName "SMS_Client" -ErrorAction SilentlyContinue
                        
                        if ($sccmClient -and ($rebootHandler -eq "SCCM")) {
                            Write-ToLog "SCCM client detected - using managed restart (user controlled)" "Green"

                            $ccmRestartPath = "$env:windir\CCM\CcmRestart.exe"
                            $regPath = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData'
                            
                            try {
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
                                    
                                    # Ensure registry path exists
                                    if (-not (Test-Path $regPath)) {
                                        New-Item -Path $regPath -Force | Out-Null
                                    }
                                    
                                    # Check the intended exit code to determine restart type
                                    $intendedExitCode = if ($ModsResult.ExitCode) { $ModsResult.ExitCode } else { 3010 }
                                        
                                    if ($intendedExitCode -eq 1641) {
                                        # HARD/MANDATORY REBOOT in SCCM registry (show UI to user, doesn't execute automatically!)
                                        $restartTime = [DateTimeOffset]::Now.AddMinutes($rebootDelay).ToUnixTimeSeconds()
                                        
                                        # CRITICAL: Both RebootBy and OverrideRebootWindowTime must be set to the same value
                                        New-ItemProperty -Path $regPath -Name 'RebootBy' -Value ([Int64]$restartTime) -PropertyType QWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'OverrideRebootWindowTime' -Value ([Int64]$restartTime) -PropertyType QWord -Force | Out-Null
                                        
                                        # Mandatory reboot settings
                                        New-ItemProperty -Path $regPath -Name 'PreferredRebootWindowTypes' -Value @("3") -PropertyType MultiString -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'OverrideRebootWindow' -Value 1 -PropertyType DWord -Force | Out-Null
                                        
                                        # Ignore service window settings
                                        New-ItemProperty -Path $regPath -Name 'OverrideServiceWindows' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'RebootOutsideOfServiceWindow' -Value 1 -PropertyType DWord -Force | Out-Null
                                        
                                        # Hard reboot settings
                                        New-ItemProperty -Path $regPath -Name 'HardReboot' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'NotifyUI' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'RebootValueInUTC' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'SetTime' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'GraceSeconds' -Value 0 -PropertyType DWord -Force | Out-Null

                                        # HARD/MANDATORY REBOOT via Task Scheduler (for execution, unless user executed it manually via UI)
                                        $taskName = "WAU_MandatoryRestart"
                                        $taskPath = "\WAU\"

                                        # Create a self destroying scheduled task for mandatory restart
                                        Write-ToLog "Creating scheduled task for mandatory restart in $rebootDelay minutes" "Yellow"

                                        # Create PowerShell script with enhanced logging
                                        $scriptContent = @"
`$regPath = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData'
`$ccmRestartPath = "`$env:windir\CCM\CcmRestart.exe"
`$logPath = "$WorkingDir\logs\mandatory_restart.log"

# Function to write to log
function Write-RestartLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "`$timestamp - `$Message" | Out-File -FilePath `$logPath -Append -Encoding UTF8
}

Write-RestartLog "Mandatory restart task started"

# Only run if RebootBy and OverrideRebootWindowTime exists under the key (if not: the user has already restarted the client)
`$regProps = Get-ItemProperty -Path `$regPath -ErrorAction SilentlyContinue
if (`$regProps.PSObject.Properties.Name -contains 'RebootBy' -and `$regProps.PSObject.Properties.Name -contains 'OverrideRebootWindowTime') {
    Write-RestartLog "SCCM restart registry values found, proceeding with restart"
    
    if (-not (Test-Path `$regPath)) { 
        New-Item -Path `$regPath -Force 
        Write-RestartLog "Created registry path: `$regPath"
    }
    
    'RebootBy','OverrideRebootWindowTime' | ForEach-Object { 
        New-ItemProperty -Path `$regPath -Name `$_ -Value ([Int64]-1) -PropertyType QWord -Force 
    }
    'PreferredRebootWindowTypes' | ForEach-Object { 
        New-ItemProperty -Path `$regPath -Name `$_ -Value @('3') -PropertyType MultiString -Force 
    }
    'OverrideRebootWindow','HardReboot','NotifyUI','RebootValueInUTC','SetTime','OverrideServiceWindows','RebootOutsideOfServiceWindow' | ForEach-Object { 
        New-ItemProperty -Path `$regPath -Name `$_ -Value 1 -PropertyType DWord -Force 
    }
    New-ItemProperty -Path `$regPath -Name 'GraceSeconds' -Value 0 -PropertyType DWord -Force
    
    Write-RestartLog "Registry values updated for mandatory restart"
    
    # Check if CcmRestart.exe exists and use it, otherwise restart the service
    if (Test-Path `$ccmRestartPath) {
        Write-RestartLog "Executing CcmRestart.exe"
        Start-Process -FilePath `$ccmRestartPath -NoNewWindow -Wait -ErrorAction SilentlyContinue
        Write-RestartLog "CcmRestart.exe execution completed"
    } else {
        Write-RestartLog "CcmRestart.exe not found, restarting ccmexec service"
        Restart-Service ccmexec -Force -ErrorAction SilentlyContinue
        Write-RestartLog "ccmexec service restart completed"
    }
} else {
    Write-RestartLog "No SCCM restart registry values found, task completed without action"
}

Write-RestartLog "Mandatory restart task completed"
"@
                                                    
                                        # Encode to Base64
                                        $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptContent))
                                        
                                        # Create action with encoded command
                                        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedScript"
                                        
                                        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($rebootDelay)
                                        # Set EndBoundary to make DeleteExpiredTaskAfter work
                                        $trigger.EndBoundary = (Get-Date).AddMinutes($rebootDelay).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss")
                                        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -DeleteExpiredTaskAfter (New-TimeSpan -Seconds 0)
                                        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                                        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Mandatory Restart by SCCM" -Force | Out-Null
                                        } else {
                                        # SOFT/NON-MANDATORY REBOOT
                                        Write-ToLog "Using soft reboot (non-mandatory) for SCCM restart" "Cyan"
                                        
                                        # For non-mandatory, RebootBy should be 0 to show dialog immediately
                                        New-ItemProperty -Path $regPath -Name 'RebootBy' -Value 0 -PropertyType QWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'OverrideRebootWindowTime' -Value 0 -PropertyType QWord -Force | Out-Null
                                        
                                        # Set as non-mandatory reboot
                                        New-ItemProperty -Path $regPath -Name 'PreferredRebootWindowTypes' -Value @("4") -PropertyType MultiString -Force | Out-Null
                                        
                                        # Soft reboot settings
                                        New-ItemProperty -Path $regPath -Name 'HardReboot' -Value 0 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'NotifyUI' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'RebootValueInUTC' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'SetTime' -Value 1 -PropertyType DWord -Force | Out-Null
                                        New-ItemProperty -Path $regPath -Name 'GraceSeconds' -Value 300 -PropertyType DWord -Force | Out-Null  # Default grace period of 5 minutes
                                    }
                                    
                                    # Try CcmRestart.exe first for notification
                                    if (Test-Path $ccmRestartPath) {
                                        Write-ToLog "Triggering SCCM restart notification via CcmRestart.exe" "Cyan"
                                        Start-Process -FilePath $ccmRestartPath -NoNewWindow -Wait -ErrorAction SilentlyContinue
                                    } else {
                                        Write-ToLog "CcmRestart.exe not found, restarting ccmexec service" "Yellow"
                                        Restart-Service ccmexec -Force -ErrorAction SilentlyContinue
                                    }
                                    
                                    if ($intendedExitCode -eq 1641) {
                                        Write-ToLog "MANDATORY restart via scheduled task: In $rebootDelay minutes" "Green"
                                    } else {
                                        Write-ToLog "Non-mandatory restart dialog triggered" "Green"
                                    }
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
                            # Standard shutdown when SCCM is not available (or reboot handler is not "SCCM")
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