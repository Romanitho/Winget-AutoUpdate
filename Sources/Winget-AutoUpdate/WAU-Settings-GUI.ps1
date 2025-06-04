#Requires -Version 5.1

<#
.SYNOPSIS
WAU Settings GUI - Configure Winget-AutoUpdate settings after installation

.DESCRIPTION
Provides a user-friendly interface to modify every aspect of WAU settings including:
- Notification levels
- Update intervals and timing
- Managing scheduled tasks
- Creating/removing shortcuts
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Managing log files
- Updating WAU configuration in the registry   
- Starting WAU manually

.NOTES
Must be run as Administrator
#>

# Import required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

# Constants of most used paths and arguments
$Script:WAU_REGISTRY_PATH = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
$Script:WAU_POLICIES_PATH = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
$Script:CONHOST_EXE = "${env:SystemRoot}\System32\conhost.exe"
$Script:POWERSHELL_ARGS = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File"
$Script:DESKTOP_RUN_WAU = "${env:Public}\Desktop\Run WAU.lnk"
$Script:USER_RUN_SCRIPT = "User-Run.ps1"
$Script:DESKTOP_WAU_SETTINGS = "${env:Public}\Desktop\WAU Settings (Administrator).lnk"
$Script:DESKTOP_WAU_APPINSTALLER = "${env:Public}\Desktop\WAU App Installer.lnk"
$Script:STARTMENU_WAU_DIR = "${env:PROGRAMDATA}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate"

# Get current script directory
$Script:WorkingDir = $PSScriptRoot

<# FUNCTIONS #>

# 1. Utility functions (no dependencies)
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Add-Shortcut ($Shortcut, $Target, $StartIn, $Arguments, $Icon, $Description, $WindowStyle = "Normal") {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $ShortcutObj = $WScriptShell.CreateShortcut($Shortcut)
    $ShortcutObj.TargetPath = $Target
    if (![string]::IsNullOrWhiteSpace($StartIn)) {
        $ShortcutObj.WorkingDirectory = $StartIn
    }
    $ShortcutObj.Arguments = $Arguments
    if (![string]::IsNullOrWhiteSpace($Icon)) {
        $ShortcutObj.IconLocation = $Icon
    }
    $ShortcutObj.Description = $Description
    switch ($WindowStyle.ToLower()) {
        "minimized" { $ShortcutObj.WindowStyle = 7 }
        "maximized" { $ShortcutObj.WindowStyle = 3 }
        default     { $ShortcutObj.WindowStyle = 1 }
    }
    $ShortcutObj.Save()

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ShortcutObj) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell) | Out-Null
}
function Test-WAUInstalledIcon {
    param (
        [Parameter(Mandatory=$true)]
        [string]$displayName
    )

    $uninstallKeys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $matchingApps = @()
    
    foreach ($key in $uninstallKeys) {
        try {
            $subKeys = Get-ChildItem -Path $key -ErrorAction Stop
            foreach ($subKey in $subKeys) {
                try {
                    $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction Stop
                    if ($properties.DisplayName -like "$displayName") {
                        # $matchingApps += $properties.DisplayName
                        $parentKeyName = Split-Path -Path $subKey.PSPath -Leaf
                        $matchingApps += $parentKeyName
                    }
                }
                catch {
                    continue
                }
            }
        }
        catch {
            continue
        }
    }

    return $matchingApps
}

# 2. Configuration functions
function Get-WAUCurrentConfig {
    try {
        $config = Get-ItemProperty -Path $Script:WAU_REGISTRY_PATH -ErrorAction SilentlyContinue
        if (!$config) {
            throw "WAU not found in registry"
        }
        return $config
    }
    catch {
        [System.Windows.MessageBox]::Show("WAU configuration not found. Please ensure WAU is properly installed.", "Error", "OK", "Error")
        exit 1
    }
}
function Update-WAUScheduledTask {
    param([hashtable]$Settings)
    
    try {
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if (!$task) { 
            [System.Windows.MessageBox]::Show("No scheduled task found: $($_.Exception.Message)", "Error", "OK", "Error")
            return 
        }
        
        # Get current triggers
        $currentTriggers = $task.Triggers
        $configChanged = $false

        # Check if LogOn trigger setting has changed (same logic as WAU-Policies)
        $hasLogonTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" }
        if (($Settings.WAU_UpdatesAtLogon -eq 1 -and -not $hasLogonTrigger) -or 
            ($Settings.WAU_UpdatesAtLogon -ne 1 -and $hasLogonTrigger)) {
            $configChanged = $true
        }

        # Check if schedule type has changed (same logic as WAU-Policies)
        $currentIntervalType = "None"
        foreach ($trigger in $currentTriggers) {
            if ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 1) {
                $currentIntervalType = "Daily"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 2) {
                $currentIntervalType = "BiDaily"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 1) {
                $currentIntervalType = "Weekly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 2) {
                $currentIntervalType = "BiWeekly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 4) {
                $currentIntervalType = "Monthly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskTimeTrigger" -and [DateTime]::Parse($trigger.StartBoundary) -lt (Get-Date)) {
                $currentIntervalType = "Never"
                break
            }
        }

        if ($currentIntervalType -ne $Settings.WAU_UpdatesInterval) {
            $configChanged = $true
        }

        # Check if delay has changed (same logic as WAU-Policies)
        $randomDelay = [TimeSpan]::ParseExact($Settings.WAU_UpdatesTimeDelay, "hh\:mm", $null)
        $timeTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -ne "MSFT_TaskLogonTrigger" } | Select-Object -First 1
        if ($null -ne $timeTrigger -and $timeTrigger.RandomDelay -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
            $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
            $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
            $existingRandomDelay = New-TimeSpan -Hours $hours -Minutes $minutes
        }
        if ($existingRandomDelay -ne $randomDelay) {
            $configChanged = $true
        }

        # Check if schedule time has changed (same logic as WAU-Policies)
        if ($currentIntervalType -ne "None" -and $currentIntervalType -ne "Never") {
            if ($null -ne $timeTrigger -and $timeTrigger.StartBoundary) {
                $currentTime = [DateTime]::Parse($timeTrigger.StartBoundary).ToString("HH:mm:ss")
                if ($currentTime -ne $Settings.WAU_UpdatesAtTime) {
                    $configChanged = $true
                }
            }
        }

        # Only update triggers if configuration has changed (same logic as WAU-Policies)
        if ($configChanged) {
            
            # Build new triggers array (same logic as WAU-Policies)
            $taskTriggers = @()
            if ($Settings.WAU_UpdatesAtLogon -eq 1) {
                $taskTriggers += New-ScheduledTaskTrigger -AtLogOn
            }
            if ($Settings.WAU_UpdatesInterval -eq "Daily") {
                $taskTriggers += New-ScheduledTaskTrigger -Daily -At $Settings.WAU_UpdatesAtTime -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "BiDaily") {
                $taskTriggers += New-ScheduledTaskTrigger -Daily -At $Settings.WAU_UpdatesAtTime -DaysInterval 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "Weekly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "BiWeekly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "Monthly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4 -RandomDelay $randomDelay
            }
            
            # If trigger(s) set
            if ($taskTriggers) {
                Set-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Trigger $taskTriggers | Out-Null
            }
            # If not, remove trigger(s) by setting past due date
            else {
                $taskTriggers = New-ScheduledTaskTrigger -Once -At "01/01/1970"
                Set-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Trigger $taskTriggers | Out-Null
            }
            
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to update scheduled task: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}

# 3. Main configuration function (depends on above)
function Set-WAUConfig {
    param(
        [hashtable]$Settings
    )
    
    try {
        # Get current configuration to compare
        $currentConfig = Get-WAUCurrentConfig
        
        # Only update registry values that have actually changed
        foreach ($key in $Settings.Keys) {
            # Skip shortcut-related settings for now - handle them separately
            if ($key -in @('WAU_StartMenuShortcut', 'WAU_AppInstallerShortcut', 'WAU_DesktopShortcut')) {
                continue
            }
            
            $currentValue = $currentConfig.$key
            $newValue = $Settings[$key]
            
            # Compare current value with new value
            if ($currentValue -ne $newValue) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name $key -Value $newValue -Force
            }
        }
        
        # Update scheduled task only if relevant settings changed
        $scheduleSettings = @('WAU_UpdatesInterval', 'WAU_UpdatesAtTime', 'WAU_UpdatesAtLogon', 'WAU_UpdatesTimeDelay')
        $scheduleChanged = $false
        foreach ($setting in $scheduleSettings) {
            if ($Settings.ContainsKey($setting) -and $currentConfig.$setting -ne $Settings[$setting]) {
                $scheduleChanged = $true
                break
            }
        }
        
        if ($scheduleChanged) {
            Update-WAUScheduledTask -Settings $Settings
        }

        # Find current WAU installation icon
        $GUID = Test-WAUInstalledIcon -DisplayName "Winget-AutoUpdate"
        $icon = "${env:SystemRoot}\Installer\${GUID}\icon.ico"

        # Handle Start Menu shortcuts
        if ($Settings.ContainsKey('WAU_StartMenuShortcut')) {
            $currentStartMenuSetting = $currentConfig.WAU_StartMenuShortcut
            $newStartMenuSetting = $Settings['WAU_StartMenuShortcut']
            
            if ($currentStartMenuSetting -ne $newStartMenuSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_StartMenuShortcut' -Value $newStartMenuSetting -Force
                
                if ($newStartMenuSetting -eq 1) {
                    if (-not (Test-Path $Script:STARTMENU_WAU_DIR)) {
                        New-Item -Path $Script:STARTMENU_WAU_DIR -ItemType Directory | Out-Null
                    }
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Run WAU.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$icon" "Run Winget AutoUpdate" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Open Logs.lnk" "$($currentConfig.InstallLocation)logs" "" "" "" "Open WAU Logs" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\WAU App Installer.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$icon" "Search for and Install WinGet Apps, etc..." "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\WAU Settings (Administrator).lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Settings-GUI.ps1`"" "$icon" "Configure Winget-AutoUpdate settings after installation" "Normal"
                }
                else {
                    if (Test-Path $Script:STARTMENU_WAU_DIR) {
                        Remove-Item -Path $Script:STARTMENU_WAU_DIR -Recurse -Force
                    }
                    
                    # Create desktop shortcut for WAU Settings if Start Menu shortcuts are removed
                    if (-not (Test-Path $Script:DESKTOP_WAU_SETTINGS)) {
                        Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Settings-GUI.ps1`"" "$icon" "Configure Winget-AutoUpdate settings after installation" "Normal"
                    }
                }
            }
        }

        # Handle App Installer shortcut
        if ($Settings.ContainsKey('WAU_AppInstallerShortcut')) {
            $currentAppInstallerSetting = $currentConfig.WAU_AppInstallerShortcut
            $newAppInstallerSetting = $Settings['WAU_AppInstallerShortcut']
            
            if ($currentAppInstallerSetting -ne $newAppInstallerSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_AppInstallerShortcut' -Value $newAppInstallerSetting -Force
                
                if ($newAppInstallerSetting -eq 1) {
                    Add-Shortcut $Script:DESKTOP_WAU_APPINSTALLER $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$icon" "Search for and Install WinGet Apps, etc..." "Normal"
                }
                else {
                    if (Test-Path $Script:DESKTOP_WAU_APPINSTALLER) {
                        Remove-Item -Path $Script:DESKTOP_WAU_APPINSTALLER -Force
                    }
                }
            }
        }

        # Handle Desktop shortcut
        if ($Settings.ContainsKey('WAU_DesktopShortcut')) {
            $currentDesktopSetting = $currentConfig.WAU_DesktopShortcut
            $newDesktopSetting = $Settings['WAU_DesktopShortcut']
            
            if ($currentDesktopSetting -ne $newDesktopSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value $newDesktopSetting -Force
                
                if ($newDesktopSetting -eq 1) {
                    Add-Shortcut $Script:DESKTOP_RUN_WAU $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$icon" "Winget AutoUpdate" "Normal"
                }
                else {
                    if (Test-Path $Script:DESKTOP_RUN_WAU) {
                        Remove-Item -Path $Script:DESKTOP_RUN_WAU -Force
                    }
                }
            }
        }

        # Check if WAU schedule is disabled and create Run WAU desktop shortcut if needed
        if ($Settings.ContainsKey('WAU_UpdatesInterval') -and $Settings['WAU_UpdatesInterval'] -eq 'Never') {
            # Always create if it doesn't exist when schedule is disabled (regardless of desktop shortcut setting)
            if (-not (Test-Path $Script:DESKTOP_RUN_WAU)) {
                Add-Shortcut $Script:DESKTOP_RUN_WAU $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$icon" "Winget AutoUpdate" "Normal"
                # Mirror shortcut creation to registry
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value 1 -Force
            }
        }
        # Remove Run WAU desktop shortcut if schedule is enabled and desktop shortcuts are disabled
        elseif ($Settings.ContainsKey('WAU_UpdatesInterval') -and $Settings['WAU_UpdatesInterval'] -ne 'Never' -and $Settings.ContainsKey('WAU_DesktopShortcut') -and $Settings['WAU_DesktopShortcut'] -eq 0) {
            if (Test-Path $Script:DESKTOP_RUN_WAU) {
                Remove-Item -Path $Script:DESKTOP_RUN_WAU -Force
                # Mirror shortcut removal to registry
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value 0 -Force
            }
        }

        # Remove WAU Settings desktop shortcut if Start Menu shortcuts are created
        if ($Settings.ContainsKey('WAU_StartMenuShortcut') -and $Settings['WAU_StartMenuShortcut'] -eq 1) {
            if (Test-Path $Script:DESKTOP_WAU_SETTINGS) {
                Remove-Item -Path $Script:DESKTOP_WAU_SETTINGS -Force
            }
            
            # Also remove Run WAU desktop shortcut if Start Menu is created and Desktop shortcuts are disabled
            if ($Settings.ContainsKey('WAU_DesktopShortcut') -and $Settings['WAU_DesktopShortcut'] -eq 0) {
                if (Test-Path $Script:DESKTOP_RUN_WAU) {
                    Remove-Item -Path $Script:DESKTOP_RUN_WAU -Force
                    # Mirror shortcut removal to registry
                    Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value 0 -Force
                }
            }
        }

        # Mirror actual desktop shortcut status to registry
        $actualShortcutExists = Test-Path $Script:DESKTOP_RUN_WAU
        $currentDesktopSetting = $currentConfig.WAU_DesktopShortcut
        $correctRegistryValue = if ($actualShortcutExists) { 1 } else { 0 }
        
        if ($currentDesktopSetting -ne $correctRegistryValue) {
            Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value $correctRegistryValue -Force
        }
        
        return $true
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to save configuration: $($_.Exception.Message)", "Error", "OK", "Error")
        return $false
    }
}

# 4. GUI helper functions (depends on config functions)
function Update-StatusDisplay {
    param($controls)

    $interval = $controls.UpdateIntervalComboBox.SelectedItem.Tag
    if ($interval -eq "Never") {
        $controls.StatusText.Text = "Disabled"
        $controls.StatusText.Foreground = "Red"
        $controls.StatusDescription.Text = "WAU will not check for updates automatically when schedule is disabled"
        $controls.UpdateTimeTextBox.IsEnabled = $false
        $controls.RandomDelayTextBox.IsEnabled = $false
    } else {
        $controls.StatusText.Text = "Enabled"
        $controls.StatusText.Foreground = "Green"
        $controls.StatusDescription.Text = "WAU will check for updates according to the schedule below"
        $controls.UpdateTimeTextBox.IsEnabled = $true
        $controls.RandomDelayTextBox.IsEnabled = $true
    }
}
function Update-MaxLogSizeState {
    param($controls)

    $selectedValue = $controls.MaxLogFilesComboBox.SelectedItem.Content
    if ($selectedValue -eq "1") {
        $controls.MaxLogSizeComboBox.IsEnabled = $false
        $controls.MaxLogSizeComboBox.SelectedIndex = 0  # Reset to 1 MB default
    } else {
        $controls.MaxLogSizeComboBox.IsEnabled = $true
    }
}
function Update-PreReleaseCheckBoxState {
    param($controls)

    if ($controls.DisableAutoUpdateCheckBox.IsChecked) {
        $controls.UpdatePreReleaseCheckBox.IsChecked = $false
        $controls.UpdatePreReleaseCheckBox.IsEnabled = $false
    } else {
        $controls.UpdatePreReleaseCheckBox.IsEnabled = $true
    }
}
function Update-WAUGUIFromConfig {
    param($controls)
    
    # Get updated config from registry
    $updatedConfig = Get-WAUCurrentConfig
    
    # Get GPO policies from registry
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    }
    catch {
        # GPO registry key doesn't exist or can't be read
    }


    # Update Notification Level
    $notifLevel = if ($updatedConfig.WAU_NotificationLevel) { $updatedConfig.WAU_NotificationLevel } else { "Full" }
    $Controls.NotificationLevelComboBox.SelectedIndex = switch ($notifLevel) {
        "Full" { 0 }
        "SuccessOnly" { 1 }
        "None" { 2 }
        default { 0 }
    }
    
    # Update Update Interval
    $updateInterval = if ($updatedConfig.WAU_UpdatesInterval) { $updatedConfig.WAU_UpdatesInterval } else { "Never" }
    $Controls.UpdateIntervalComboBox.SelectedIndex = switch ($updateInterval) {
        "Daily" { 0 }
        "BiDaily" { 1 }
        "Weekly" { 2 }
        "BiWeekly" { 3 }
        "Monthly" { 4 }
        "Never" { 5 }
        default { 5 }
    }
    
    # Update time and delay
    $Controls.UpdateTimeTextBox.Text = if ($updatedConfig.WAU_UpdatesAtTime) { $updatedConfig.WAU_UpdatesAtTime } else { "06:00:00" }
    $Controls.RandomDelayTextBox.Text = if ($updatedConfig.WAU_UpdatesTimeDelay) { $updatedConfig.WAU_UpdatesTimeDelay } else { "00:00" }
    
    # Update paths
    $Controls.ListPathTextBox.Text = if ($updatedConfig.WAU_ListPath) { $updatedConfig.WAU_ListPath } else { "" }
    $Controls.ModsPathTextBox.Text = if ($updatedConfig.WAU_ModsPath) { $updatedConfig.WAU_ModsPath } else { "" }
    $Controls.AzureBlobSASURLTextBox.Text = if ($updatedConfig.WAU_AzureBlobSASURL) { $updatedConfig.WAU_AzureBlobSASURL } else { "" }
    
    # Update checkboxes
    $Controls.UpdatesAtLogonCheckBox.IsChecked = ($updatedConfig.WAU_UpdatesAtLogon -eq 1)
    $Controls.DoNotRunOnMeteredCheckBox.IsChecked = ($updatedConfig.WAU_DoNotRunOnMetered -eq 1)
    $Controls.UserContextCheckBox.IsChecked = ($updatedConfig.WAU_UserContext -eq 1)
    $Controls.BypassListForUsersCheckBox.IsChecked = ($updatedConfig.WAU_BypassListForUsers -eq 1)
    $Controls.DisableAutoUpdateCheckBox.IsChecked = ($updatedConfig.WAU_DisableAutoUpdate -eq 1)
    $Controls.UpdatePreReleaseCheckBox.IsChecked = ($updatedConfig.WAU_UpdatePreRelease -eq 1)
    $Controls.UseWhiteListCheckBox.IsChecked = ($updatedConfig.WAU_UseWhiteList -eq 1)
    $Controls.AppInstallerShortcutCheckBox.IsChecked = ($updatedConfig.WAU_AppInstallerShortcut -eq 1)
    $Controls.DesktopShortcutCheckBox.IsChecked = ($updatedConfig.WAU_DesktopShortcut -eq 1)
    $Controls.StartMenuShortcutCheckBox.IsChecked = ($updatedConfig.WAU_StartMenuShortcut -eq 1)
    
    # Update log settings
    $maxLogFiles = if ($null -ne $updatedConfig.WAU_MaxLogFiles) { $updatedConfig.WAU_MaxLogFiles } else { "3" }
    try {
        $maxLogFilesInt = [int]$maxLogFiles
        if ($maxLogFilesInt -ge 0 -and $maxLogFilesInt -le 99) {
            $Controls.MaxLogFilesComboBox.SelectedIndex = $maxLogFilesInt
        } else {
            $Controls.MaxLogFilesComboBox.SelectedIndex = 3  # Default fallback
        }
    } catch {
        $Controls.MaxLogFilesComboBox.SelectedIndex = 3  # Default fallback
    }

    # Update log size
    $maxLogSize = if ($updatedConfig.WAU_MaxLogSize) { $updatedConfig.WAU_MaxLogSize } else { "1048576" }
    $logSizeIndex = -1
    try {
        for ($i = 0; $i -lt $Controls.MaxLogSizeComboBox.Items.Count; $i++) {
            if ($Controls.MaxLogSizeComboBox.Items[$i].Tag -eq $maxLogSize) {
                $logSizeIndex = $i
                break
            }
        }
    }
    catch {
        $logSizeIndex = 0  # Fallback to first item
    }

    if ($logSizeIndex -ge 0) {
        $Controls.MaxLogSizeComboBox.SelectedIndex = $logSizeIndex
    } else {
        $Controls.MaxLogSizeComboBox.Text = $maxLogSize
    }

    # Update information section
    $Controls.VersionText.Text = "Version: $($updatedConfig.ProductVersion)"
    $Controls.InstallLocationText.Text = "Install Location: $($updatedConfig.InstallLocation)"

    # Update WAU AutoUpdate status
    $wauAutoUpdateDisabled = ($updatedConfig.WAU_DisableAutoUpdate -eq 1)
    $wauPreReleaseEnabled = ($updatedConfig.WAU_UpdatePreRelease -eq 1)
    $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
    $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)

    # Helper function to colorize status text
    function Get-ColoredStatusText($label, $enabled, $enabledText = "Enabled", $disabledText = "Disabled") {
        $color = if ($enabled) { "#228B22" } else { "#FF6666" } # Forest green or light red
        $status = if ($enabled) { $enabledText } else { $disabledText }
        return "{0}: <Run Foreground='{1}'>{2}</Run>" -f $label, $color, $status
    }

    # Compose colored status text using Inlines (for TextBlock with Inlines)
    $statusText = @(
        Get-ColoredStatusText "WAU AutoUpdate" (-not $wauAutoUpdateDisabled)
        Get-ColoredStatusText "WAU PreRelease" $wauPreReleaseEnabled
        Get-ColoredStatusText "GPO Management" $wauActivateGPOManagementEnabled
        Get-ColoredStatusText "Daily GPO Task Status" $wauRunGPOManagementEnabled
    ) -join " | "

    # Set the Inlines property for colorized text
    $Controls.WAUAutoUpdateText.Inlines.Clear()
    [void]$Controls.WAUAutoUpdateText.Inlines.Add([Windows.Markup.XamlReader]::Parse("<Span xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>$statusText</Span>"))

    # Trigger status update
    Update-StatusDisplay -Controls $controls
    Update-MaxLogSizeState -Controls $controls
    Update-PreReleaseCheckBoxState -Controls $controls
}

# 5. Manual start function
function Start-WAUManually {
    try {
        $currentConfig = Get-WAUCurrentConfig
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if ($task) {
            Start-Process -FilePath $Script:CONHOST_EXE `
                -ArgumentList "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" `
                -ErrorAction Stop
            [System.Windows.MessageBox]::Show("WAU update task started successfully!", "Success", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("WAU scheduled task not found!", "Error", "OK", "Error")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to start WAU: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}

# 6. GUI function (depends on most others)
function Show-WAUSettingsGUI {
    
    # Get current configuration
    $currentConfig = Get-WAUCurrentConfig
    
    # Create XAML for the form
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" 
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="WAU Settings (Administrator)" Height="820" Width="600" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
    FontSize="11">
    <Grid Margin="10">
    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    
    <!-- WAU Status -->
    <GroupBox Grid.Row="1" Header="WAU Status" Margin="0,0,0,10">
        <StackPanel Margin="10">
        <StackPanel Orientation="Horizontal">
            <TextBlock Text="Schedule:" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock x:Name="StatusText" Text="Enabled" Foreground="Green" FontWeight="Bold" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="StatusDescription" Text="WAU will check for updates according to the schedule below" FontSize="10" Foreground="Gray" Margin="0,5,0,0"/>
        </StackPanel>
    </GroupBox>
    
    <!-- Update Interval and Notification Level (Combined) -->
    <GroupBox Grid.Row="2" Header="Update Interval &amp; Notifications" Margin="0,0,0,10">
        <Grid Margin="10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <!-- Update Interval Column -->
            <StackPanel Grid.Column="0" Margin="0,0,5,0">
                <ComboBox x:Name="UpdateIntervalComboBox" Height="25" Width="Auto">
                    <ComboBoxItem Content="Daily" Tag="Daily"/>
                    <ComboBoxItem Content="Every 2 Days" Tag="BiDaily"/>
                    <ComboBoxItem Content="Weekly" Tag="Weekly"/>
                    <ComboBoxItem Content="Every 2 Weeks" Tag="BiWeekly"/>
                    <ComboBoxItem Content="Monthly" Tag="Monthly"/>
                    <ComboBoxItem Content="Never (Disable)" Tag="Never"/>
                </ComboBox>
                <TextBlock Text="How often WAU checks for updates" 
                           FontSize="10" Foreground="Gray" Margin="0,5,0,0"
                           TextWrapping="Wrap"/>
            </StackPanel>
            <!-- Notification Level Column -->
            <StackPanel Grid.Column="1" Margin="5,0,0,0">
                <ComboBox x:Name="NotificationLevelComboBox" Height="25" Width="Auto">
                    <ComboBoxItem Content="Full" Tag="Full"/>
                    <ComboBoxItem Content="Success Only" Tag="SuccessOnly"/>
                    <ComboBoxItem Content="None" Tag="None"/>
                </ComboBox>
                <TextBlock Text="Level of notifications" 
                           FontSize="10" Foreground="Gray" Margin="0,5,0,0"
                           TextWrapping="Wrap"/>
            </StackPanel>
        </Grid>
    </GroupBox>

    <!-- Update Time and Random Delay -->
    <GroupBox Grid.Row="3" Header="Update Time &amp; Random Delay" Margin="0,0,0,10">
        <Grid Margin="10">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>
        <!-- Update Time Column -->
        <StackPanel Grid.Column="0" Margin="0,0,5,0">
            <StackPanel Orientation="Horizontal">
            <TextBox x:Name="UpdateTimeTextBox" Width="80" Height="25" Text="06:00:00" VerticalContentAlignment="Center"/>
            <TextBlock Text="(HH:mm:ss format)" VerticalAlignment="Center" Margin="10,0,0,0" FontSize="10" Foreground="Gray"/>
            </StackPanel>
            <TextBlock Text="Time of day when updates are checked" FontSize="10" Foreground="Gray" Margin="0,5,0,0"/>
        </StackPanel>
        <!-- Random Delay Column -->
        <StackPanel Grid.Column="1" Margin="5,0,0,0">
            <StackPanel Orientation="Horizontal">
            <TextBox x:Name="RandomDelayTextBox" Width="60" Height="25" Text="00:00" VerticalContentAlignment="Center"/>
            <TextBlock Text="(HH:mm format)" VerticalAlignment="Center" Margin="10,0,0,0" FontSize="10" Foreground="Gray"/>
            </StackPanel>
            <TextBlock Text="Maximum random delay after scheduled time" FontSize="10" Foreground="Gray" Margin="0,5,0,0"/>
        </StackPanel>
        </Grid>
    </GroupBox>
    
    <!-- List and Mods Definitions -->
    <GroupBox Grid.Row="4" Header="List &amp; Mods Definitions" Margin="0,0,0,10">
        <StackPanel Margin="10,10,10,10">
        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
            <TextBlock Text="External List Path (dir only):" Width="160" VerticalAlignment="Center"/>
            <TextBox x:Name="ListPathTextBox" Width="372" Height="25" VerticalContentAlignment="Center">
            <TextBox.ToolTip>
                <TextBlock>
                Path for external list files. Can be URL, UNC path, local path or 'GPO'. If set to 'GPO', ensure you also configure the list/lists in GPO!
                </TextBlock>
            </TextBox.ToolTip>
            </TextBox>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
            <TextBlock Text="External Mods Path:" Width="160" VerticalAlignment="Center"/>
            <TextBox x:Name="ModsPathTextBox" Width="372" Height="25" VerticalContentAlignment="Center">
            <TextBox.ToolTip>
                <TextBlock>
                Path for external mods. Can be URL, UNC path, local path or 'AzureBlob'. If set to 'AzureBlob', ensure you also configure 'Azure Blob SAS URL' below!
                </TextBlock>
            </TextBox.ToolTip>
            </TextBox>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,0">
            <TextBlock Text="Azure Blob SAS URL:" Width="160" VerticalAlignment="Center"/>
            <TextBox x:Name="AzureBlobSASURLTextBox" Width="372" Height="25" VerticalContentAlignment="Center">
            <TextBox.ToolTip>
                <TextBlock>
                Azure Storage Blob URL with SAS token for use with the 'Mods' feature. The URL must include the SAS token and have 'read' and 'list' permissions.
                </TextBlock>
            </TextBox.ToolTip>
            </TextBox>
        </StackPanel>
        </StackPanel>
    </GroupBox>

    <!-- Additional Options -->
    <GroupBox Grid.Row="5" Header="Additional Options" Margin="0,0,0,10">
        <Grid Margin="10">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <CheckBox Grid.Row="0" Grid.Column="0" x:Name="DisableAutoUpdateCheckBox" Content="Disable WAU AutoUpdate" Margin="0,0,5,5"
                ToolTip="Disable automatic updating of WAU itself"/>
        <CheckBox Grid.Row="0" Grid.Column="1" x:Name="UpdatePreReleaseCheckBox" Content="Update WAU to PreRelease" Margin="0,0,5,5"
                ToolTip="Allow WAU to update itself to pre-release versions"/>
        <CheckBox Grid.Row="0" Grid.Column="2" x:Name="DoNotRunOnMeteredCheckBox" Content="Don't run on data plan" Margin="0,0,5,5"
                ToolTip="Prevent WAU from running when connected to a metered network"/>
        <CheckBox Grid.Row="1" Grid.Column="0" x:Name="StartMenuShortcutCheckBox" Content="Start menu shortcuts" Margin="0,0,5,5"
                ToolTip="Create/delete Start menu shortcuts ('WAU Settings' will be created on Desktop if deleted!)"/>
        <CheckBox Grid.Row="1" Grid.Column="1" x:Name="DesktopShortcutCheckBox" Content="WAU Desktop shortcut" Margin="0,0,5,5"
                ToolTip="Create/delete 'Run WAU' shortcut on Desktop"/>
        <CheckBox Grid.Row="1" Grid.Column="2" x:Name="AppInstallerShortcutCheckBox" Content="App Installer Desktop shortcut" Margin="0,0,5,5"
                ToolTip="Create/delete shortcut 'WAU App Installer' on Desktop"/>
        <CheckBox Grid.Row="2" Grid.Column="0" x:Name="UpdatesAtLogonCheckBox" Content="Run at user logon" Margin="0,0,5,5"
                ToolTip="Run WAU automatically when a user logs in"/>
        <CheckBox Grid.Row="2" Grid.Column="1" x:Name="UserContextCheckBox" Content="Run in user context" Margin="0,0,5,5"
                ToolTip="Run WAU also in the current user's context"/>
        <CheckBox Grid.Row="2" Grid.Column="2" x:Name="BypassListForUsersCheckBox" Content="Bypass list in user context" Margin="0,0,5,5"
                ToolTip="Ignore the black/white list when running in user context"/>
        <CheckBox Grid.Row="3" Grid.Column="0" x:Name="UseWhiteListCheckBox" Content="Use whitelist" Margin="0,0,5,0"
                ToolTip="Only update apps that are included in a whitelist"/>
        </Grid>
    </GroupBox>
    
    <!-- Log Files Management -->
    <GroupBox Grid.Row="6" Header="Log Files Management" Margin="0,0,0,10">
        <Grid Margin="10">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>
        <!-- MaxLogFiles column -->
        <StackPanel Grid.Column="0" Margin="0,0,5,0">
            <StackPanel Orientation="Horizontal">
            <ComboBox x:Name="MaxLogFilesComboBox" Width="60" Height="25" SelectedIndex="3" VerticalContentAlignment="Center">
                <ComboBox.ToolTip>
                    <TextBlock>
                        Set to '0' to never delete old logs, '1' to keep only the original and let it grow
                    </TextBlock>
                </ComboBox.ToolTip>
            </ComboBox>
            <TextBlock Text="(0-99, default 3)" VerticalAlignment="Center" Margin="10,0,0,0" FontSize="10" Foreground="Gray"/>
            </StackPanel>
            <TextBlock Text="Number of allowed log files" FontSize="10" Foreground="Gray" Margin="0,5,0,0"/>
        </StackPanel>
        <!-- MaxLogSize column -->
        <StackPanel Grid.Column="1" Margin="5,0,0,0">
            <StackPanel Orientation="Horizontal">
            <ComboBox x:Name="MaxLogSizeComboBox" Width="70" Height="25" SelectedIndex="0" VerticalContentAlignment="Center" IsEditable="True">
                <ComboBox.ToolTip>
                    <TextBlock>
                        Maximum size of each log file before rotation occurs (Bytes if manually entered!)
                    </TextBlock>
                </ComboBox.ToolTip>
                <ComboBoxItem Content="1 MB" Tag="1048576"/>
                <ComboBoxItem Content="2 MB" Tag="2097152"/>
                <ComboBoxItem Content="3 MB" Tag="3145728"/>
                <ComboBoxItem Content="4 MB" Tag="4194304"/>
                <ComboBoxItem Content="5 MB" Tag="5242880"/>
                <ComboBoxItem Content="6 MB" Tag="6291456"/>
                <ComboBoxItem Content="7 MB" Tag="7340032"/>
                <ComboBoxItem Content="8 MB" Tag="8388608"/>
                <ComboBoxItem Content="9 MB" Tag="9437184"/>
                <ComboBoxItem Content="10 MB" Tag="10485760"/>
            </ComboBox>
            <TextBlock Text="(1-10 MB, default 1 MB)" VerticalAlignment="Center" Margin="10,0,0,0" FontSize="10" Foreground="Gray"/>
            </StackPanel>
            <TextBlock Text="Size of the log file before rotating" FontSize="10" Foreground="Gray" Margin="0,5,0,0"/>
        </StackPanel>
        </Grid>
    </GroupBox>

    <!-- Information -->
    <GroupBox Grid.Row="7" Header="Information" Margin="0,0,0,10">
        <StackPanel Margin="10">
            <TextBlock x:Name="VersionText" Text="Version: " FontSize="9"/>
            <TextBlock x:Name="InstallLocationText" Text="Install Location: " FontSize="9"/>
            <TextBlock x:Name="WAUAutoUpdateText" Text="WAU AutoUpdate: " FontSize="9"/>
        </StackPanel>
    </GroupBox>
    
    <!-- Status Bar -->
    <TextBlock Grid.Row="8" x:Name="StatusBarText" Text="" FontSize="10" Foreground="Gray" VerticalAlignment="Bottom"/>
    
    <!-- Buttons -->
    <StackPanel Grid.Row="9" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
        <Button x:Name="RunNowButton" Content="Run WAU" Width="100" Height="30" Margin="0,0,10,0"/>
        <Button x:Name="OpenLogsButton" Content="Open Logs" Width="100" Height="30" Margin="0,0,20,0"/>
        <Button x:Name="SaveButton" Content="Save Settings" Width="100" Height="30" Margin="0,0,10,0" IsDefault="True"/>
        <Button x:Name="CancelButton" Content="Cancel" Width="80" Height="30"/>
    </StackPanel>
    </Grid>
</Window>
"@
    # Load XAML
    [xml]$xamlXML = $xaml -replace 'x:N', 'N'
    $reader = (New-Object System.Xml.XmlNodeReader $xamlXML)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Icon = $IconBase64
    
    # Get controls
    $controls = @{}
    $xamlXML.SelectNodes("//*[@Name]") | ForEach-Object {
        $controls[$_.Name] = $window.FindName($_.Name)
    }
    
    # Set initial values for MaxLogFiles ComboBox programmatically
    0..99 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$_
        $controls.MaxLogFilesComboBox.Items.Add($item) | Out-Null
    }

    # Event handler for interval change
    $controls.UpdateIntervalComboBox.Add_SelectionChanged({
        Update-StatusDisplay -Controls $controls
    })
    
    # Event handler for DisableAutoUpdate checkbox
    $controls.DisableAutoUpdateCheckBox.Add_Checked({
        Update-PreReleaseCheckBoxState -Controls $controls
    })
    
    $controls.DisableAutoUpdateCheckBox.Add_Unchecked({
        Update-PreReleaseCheckBoxState -Controls $controls
    })

    # Event handler for MaxLogFiles change
    $controls.MaxLogFilesComboBox.Add_SelectionChanged({
        Update-MaxLogSizeState -Controls $controls
    })
    
    # Populate current settings
    Update-WAUGUIFromConfig -Controls $controls    

    # Event handlers for controls
    $controls.SaveButton.Add_Click({
        # Validate time format
        try {
            [datetime]::ParseExact($controls.UpdateTimeTextBox.Text, "HH:mm:ss", $null) | Out-Null
        }
        catch {
            [System.Windows.MessageBox]::Show("Invalid time format. Please use HH:mm:ss format (e.g., 06:00:00)", "Error", "OK", "Error")
            return
        }
        
        # Validate random delay format
        try {
            [datetime]::ParseExact($controls.RandomDelayTextBox.Text, "HH:mm", $null) | Out-Null
        }
        catch {
            [System.Windows.MessageBox]::Show("Invalid time format. Please use HH:mm format (e.g., 00:00)", "Error", "OK", "Error")
            return
        }

        # Prepare settings hashtable
        $newSettings = @{
            WAU_NotificationLevel = $controls.NotificationLevelComboBox.SelectedItem.Tag
            WAU_UpdatesInterval = $controls.UpdateIntervalComboBox.SelectedItem.Tag
            WAU_UpdatesAtTime = $controls.UpdateTimeTextBox.Text
            WAU_UpdatesTimeDelay = $controls.RandomDelayTextBox.Text
            WAU_ListPath = $controls.ListPathTextBox.Text
            WAU_ModsPath = $controls.ModsPathTextBox.Text
            WAU_AzureBlobSASURL = $controls.AzureBlobSASURLTextBox.Text
            WAU_MaxLogFiles = $controls.MaxLogFilesComboBox.SelectedItem.Content
            WAU_MaxLogSize = if ($controls.MaxLogSizeComboBox.SelectedItem -and $controls.MaxLogSizeComboBox.SelectedItem.Tag) { $controls.MaxLogSizeComboBox.SelectedItem.Tag } else { $controls.MaxLogSizeComboBox.Text }
            WAU_UpdatesAtLogon = if ($controls.UpdatesAtLogonCheckBox.IsChecked) { 1 } else { 0 }
            WAU_DoNotRunOnMetered = if ($controls.DoNotRunOnMeteredCheckBox.IsChecked) { 1 } else { 0 }
            WAU_UserContext = if ($controls.UserContextCheckBox.IsChecked) { 1 } else { 0 }
            WAU_BypassListForUsers = if ($controls.BypassListForUsersCheckBox.IsChecked) { 1 } else { 0 }
            WAU_DisableAutoUpdate = if ($controls.DisableAutoUpdateCheckBox.IsChecked) { 1 } else { 0 }
            WAU_UpdatePreRelease = if ($controls.DisableAutoUpdateCheckBox.IsChecked) { 0 } elseif ($controls.UpdatePreReleaseCheckBox.IsChecked) { 1 } else { 0 }
            WAU_UseWhiteList = if ($controls.UseWhiteListCheckBox.IsChecked) { 1 } else { 0 }
            WAU_AppInstallerShortcut = if ($controls.AppInstallerShortcutCheckBox.IsChecked) { 1 } else { 0 }
            WAU_DesktopShortcut = if ($controls.DesktopShortcutCheckBox.IsChecked) { 1 } else { 0 }
            WAU_StartMenuShortcut = if ($controls.StartMenuShortcutCheckBox.IsChecked) { 1 } else { 0 }
        }
        
        # Save settings
        if (Set-WAUConfig -Settings $newSettings) {
            [System.Windows.MessageBox]::Show("Settings have been saved successfully!", "Success", "OK", "Information")

            # Updating settings in-place
            Update-WAUGUIFromConfig -Controls $controls

        } else {
            [System.Windows.MessageBox]::Show("Failed to save settings.", "Error", "OK", "Error")
        }
    })
    
    $controls.CancelButton.Add_Click({
        $window.Close()
    })
    
    $controls.RunNowButton.Add_Click({
        Start-WAUManually
    })

    # Handle Enter key to save settings
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq 'Return' -or $_.Key -eq 'Enter') {
            $controls.SaveButton.RaiseEvent([Windows.RoutedEventArgs][Windows.Controls.Primitives.ButtonBase]::ClickEvent)
            $_.Handled = $true
        }
    })

    # ESC key handler to close window
    $window.Add_KeyDown({
        if ($_.Key -eq "Escape") {
            $window.Close()
        }
    })
    
    $controls.OpenLogsButton.Add_Click({
        try {
            $logPath = Join-Path $currentConfig.InstallLocation "logs"
            if (Test-Path $logPath) {
                Start-Process "explorer.exe" -ArgumentList $logPath
            } else {
                [System.Windows.MessageBox]::Show("Log directory not found: $logPath", "Error", "OK", "Error")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open logs: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })
    
    # Show window
    $window.ShowDialog() | Out-Null
}

<# MAIN #>

# Check if running as administrator
if (-not (Test-Administrator)) {
    [System.Windows.MessageBox]::Show("This application must be run as Administrator to modify WAU settings.", "Administrator Required", "OK", "Warning")
    exit 1
}

# Set console encoding
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'
$IconBase64 = [Convert]::FromBase64String("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")

# Show the GUI
Show-WAUSettingsGUI
