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
$Script:WAU_TITLE = "WAU Settings (Administrator)"
$Script:DESKTOP_WAU_SETTINGS = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), "$Script:WAU_TITLE.lnk")
$Script:DESKTOP_WAU_APPINSTALLER = "${env:Public}\Desktop\WAU App Installer.lnk"
$Script:STARTMENU_WAU_DIR = "${env:PROGRAMDATA}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate"
$Script:COLOR_ENABLED = "#228B22"  # Forest green
$Script:COLOR_DISABLED = "#FF6666" # Light red
$Script:COLOR_ACTIVE = "Orange"
$Script:COLOR_INACTIVE = "Gray" # Grey
$Script:STATUS_READY_TEXT = "Ready (F12: Dev Tools)"
$Script:WAIT_TIME = 1000 # 1 second wait time for UI updates

# Get current script directory
$Script:WorkingDir = $PSScriptRoot

<# FUNCTIONS #>

# 1. Utility functions (no dependencies)
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
Function Start-PopUp ($Message) {

    if (!$PopUpWindow) {

        [xml]$XAML = ($Script:POPUP_XAML -replace "x:N", "N")

        #Read the form
        $Reader = (New-Object System.Xml.XmlNodeReader $XAML)
        $Script:PopUpWindow = [Windows.Markup.XamlReader]::Load($Reader)
        $PopUpWindow.Icon = $IconBase64

        # Make sure window stays on top (redundant, but ensures behavior)
        $PopUpWindow.Topmost = $true

        #Store Form Objects In PowerShell
        $XAML.SelectNodes("//*[@Name]") | ForEach-Object {
            Set-Variable -Name "$($_.Name)" -Value $PopUpWindow.FindName($_.Name) -Scope Script
        }

        $PopUpWindow.Show()
    }
    #Message to display
    $PopUpLabel.Text = $Message
    #Update PopUp
    $PopUpWindow.Dispatcher.Invoke([action] {}, "Render")
}
Function Close-PopUp {
    if ($null -ne $Script:PopUpWindow) {
        $Script:PopUpWindow.Close()
        $Script:PopUpWindow = $null
    }
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
function Test-InstalledWAU {
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
                        $matchingApps += $properties.DisplayVersion
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
function Get-DisplayValue {
    param (
        [string]$PropertyName,
        $Config,
        $Policies
    )
    
    # Check if GPO management is active
    $isGPOManaged = ($Policies.WAU_ActivateGPOManagement -eq 1 -and $Config.WAU_RunGPOManagement -eq 1)
    
    # These properties are always editable and taken from local config, even in GPO mode
    $alwaysFromConfig = @('WAU_AppInstallerShortcut', 'WAU_DesktopShortcut', 'WAU_StartMenuShortcut')
    
    # If GPO managed and this property exists in policies and it's not in the exceptions list
    if ($isGPOManaged -and 
        $Policies.PSObject.Properties.Name -contains $PropertyName -and
        $PropertyName -notin $alwaysFromConfig) {
        return $Policies.$PropertyName
    }
    
    # Otherwise use the local config value
    return $Config.$PropertyName
}
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
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name $key -Value $newValue -Force | Out-Null
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
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Run WAU.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$Script:WAU_ICON" "Run Winget AutoUpdate" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Open Logs.lnk" "$($currentConfig.InstallLocation)logs" "" "" "" "Open WAU Logs" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\WAU App Installer.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$Script:WAU_ICON" "Search for and Install WinGet Apps, etc..." "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\$Script:WAU_TITLE.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Settings-GUI.ps1`"" "$Script:WAU_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal"
                }
                else {
                    if (Test-Path $Script:STARTMENU_WAU_DIR) {
                        Remove-Item -Path $Script:STARTMENU_WAU_DIR -Recurse -Force
                    }
                    
                    # Create desktop shortcut for WAU Settings if Start Menu shortcuts are removed
                    if (-not (Test-Path $Script:DESKTOP_WAU_SETTINGS)) {
                        Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Settings-GUI.ps1`"" "$Script:WAU_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal"
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
                    Add-Shortcut $Script:DESKTOP_WAU_APPINSTALLER $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$Script:WAU_ICON" "Search for and Install WinGet Apps, etc..." "Normal"
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
                    Add-Shortcut $Script:DESKTOP_RUN_WAU $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$Script:WAU_ICON" "Winget AutoUpdate" "Normal"
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
                Add-Shortcut $Script:DESKTOP_RUN_WAU $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$Script:WAU_ICON" "Winget AutoUpdate" "Normal"
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
        $controls.StatusDescription.Text = "WAU will not check for updates automatically when disabled"
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
function Set-ControlsState {
    param(
        $parentControl,
        [bool]$enabled = $true,
        [string]$excludePattern = $null
    )

    $alwaysEnabledControls = @(
        'SaveButton', 'CancelButton', 'RunNowButton', 'OpenLogsButton',
        'DevTaskButton', 'DevRegButton', 'DevGUIDButton', 'DevListButton'
    )

    function Get-Children($control) {
        if ($null -eq $control) { return @() }
        $children = @()
        if ($control -is [System.Windows.Controls.Panel]) {
            $children = $control.Children
        } elseif ($control -is [System.Windows.Controls.ContentControl]) {
            if ($control.Content -and $control.Content -isnot [string]) {
                $children = @($control.Content)
            }
        } elseif ($control -is [System.Windows.Controls.ItemsControl]) {
            $children = $control.Items
        }
        return $children
    }

    function Test-ExceptionChild($control) {
        $children = Get-Children $control
        foreach ($child in $children) {
            $childName = $null
            try { $childName = $child.GetValue([System.Windows.FrameworkElement]::NameProperty) } catch {}
            if (
                ($childName -and $childName -in $alwaysEnabledControls) -or
                ($excludePattern -and $childName -and $childName -like "*$excludePattern*")
            ) {
                return $true
            }
            if (Test-ExceptionChild $child) { return $true }
        }
        return $false
    }

    $hasException = Test-ExceptionChild $parentControl

    # Only set IsEnabled=$false if there are NO exceptions in the child tree
    if ($parentControl -is [System.Windows.Controls.Control] -and $parentControl.GetType().Name -ne 'Window') {
        if ($hasException) {
            $parentControl.IsEnabled = $true
        } else {
            $parentControl.IsEnabled = $enabled
        }
    }

    $children = Get-Children $parentControl
    foreach ($control in $children) {
        $controlName = $null
        try { $controlName = $control.GetValue([System.Windows.FrameworkElement]::NameProperty) } catch {}

        $isAlwaysEnabled = $controlName -and $controlName -in $alwaysEnabledControls
        $isExcluded = $excludePattern -and $controlName -and $controlName -like "*$excludePattern*"

        if ($isAlwaysEnabled -or $isExcluded) {
            if ($control -is [System.Windows.Controls.Control]) {
                $control.IsEnabled = $true
            }
            Set-ControlsState -parentControl $control -enabled $true -excludePattern $excludePattern
        } else {
            Set-ControlsState -parentControl $control -enabled $enabled -excludePattern $excludePattern
        }
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
function Update-GPOManagementState {
    param($controls, $skipPopup = $false)
    
    # Get updated config and policies
    $updatedConfig = Get-WAUCurrentConfig
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    }
    catch {
        # GPO registry key doesn't exist or can't be read
    }

    $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
    $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)
    
    # Check if both GPO settings are enabled
    $gpoControlsActive = $wauActivateGPOManagementEnabled -and $wauRunGPOManagementEnabled
    
    if ($gpoControlsActive) {
         # Show popup only if not skipped (i.e., when window first opens)
        if (-not $skipPopup) {
            # Update status bar to show GPO is controlling settings
            $controls.StatusBarText.Text = "Settings Managed by GPO"
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE
            
            # Show popup when GPO is controlling settings with delay to ensure main window is visible first
            $controls.StatusBarText.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)  # Small delay to ensure main window is rendered
                Start-PopUp "Only shortcut settings can be modified when GPO Management is active..."
                
                # Close the popup after showing it for 3 standard wait times
                Start-Sleep -Milliseconds ($Script:WAIT_TIME * 3)
                Close-PopUp
            }) | Out-Null
        }

        # Disable all except Shortcut controls
        Set-ControlsState -parentControl $window -enabled $false -excludePattern "*Shortcut*"

    } else {
        # Enable all controls
        Set-ControlsState -parentControl $window -enabled $true
        
        # Reset status bar if it was showing GPO message
        if ($controls.StatusBarText.Text -eq "Settings Managed by GPO") {
            $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
        }

        # Make sure any popup is closed when GPO is not active
        try {
            if ($null -ne $Script:PopUpWindow) {
                Close-PopUp
            }
        }
        catch {
            # Popup might already be closed
        }
        
        # Re-apply other state updates
        Update-StatusDisplay -Controls $controls
        Update-MaxLogSizeState -Controls $controls
        Update-PreReleaseCheckBoxState -Controls $controls
    }
    
    return $gpoControlsActive
}
function Update-WAUGUIFromConfig {
    param($controls)
    
    # Get updated config and policies
    $updatedConfig = Get-WAUCurrentConfig
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    }
    catch {
        # GPO registry key doesn't exist or can't be read
    }

    $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
    $wauGPOListPathEnabled = ($updatedPolicies.WAU_ListPath -eq "GPO")
    $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)

    # Update Notification Level
    $notifLevel = Get-DisplayValue -PropertyName "WAU_NotificationLevel" -Config $updatedConfig -Policies $updatedPolicies
    $Controls.NotificationLevelComboBox.SelectedIndex = switch ($notifLevel) {
        "Full" { 0 }
        "SuccessOnly" { 1 }
        "None" { 2 }
        default { 0 }
    }
    
    # Update Update Interval
    $updateInterval = Get-DisplayValue -PropertyName "WAU_UpdatesInterval" -Config $updatedConfig -Policies $updatedPolicies
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
    $Controls.UpdateTimeTextBox.Text = (Get-DisplayValue -PropertyName "WAU_UpdatesAtTime" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $Controls.RandomDelayTextBox.Text = (Get-DisplayValue -PropertyName "WAU_UpdatesTimeDelay" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    
    # Update paths
    $Controls.ListPathTextBox.Text = (Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $Controls.ModsPathTextBox.Text = (Get-DisplayValue -PropertyName "WAU_ModsPath" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $Controls.AzureBlobSASURLTextBox.Text = (Get-DisplayValue -PropertyName "WAU_AzureBlobSASURL" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    
    # Update checkboxes
    $Controls.UpdatesAtLogonCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UpdatesAtLogon" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DoNotRunOnMeteredCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DoNotRunOnMetered" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UserContextCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UserContext" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.BypassListForUsersCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_BypassListForUsers" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DisableAutoUpdateCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DisableAutoUpdate" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UpdatePreReleaseCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UpdatePrerelease" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UseWhiteListCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UseWhiteList" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.AppInstallerShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_AppInstallerShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DesktopShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DesktopShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.StartMenuShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_StartMenuShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    
    # Update log settings
    $maxLogFiles = (Get-DisplayValue -PropertyName "WAU_MaxLogFiles" -Config $updatedConfig -Policies $updatedPolicies).ToString()
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
    $maxLogSize = (Get-DisplayValue -PropertyName "WAU_MaxLogSize" -Config $updatedConfig -Policies $updatedPolicies).ToString()
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
    $Controls.VersionText.Text = "WAU Version: $Script:WAU_VERSION | "
 
    # Get last run time for the scheduled task 'Winget-AutoUpdate'
    try {
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction Stop
        $lastRunTime = $task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastRunTime
        if ($lastRunTime -and $lastRunTime -ne [datetime]::MinValue) {
            $Controls.RunDate.Text = "Last Run: $($lastRunTime.ToString('yyyy-MM-dd HH:mm')) | "
        } else {
            $Controls.RunDate.Text = "Last Run: Never | "
        }
    } catch {
        $Controls.RunDate.Text = "Last Run: Unknown! | "
    }
    $Controls.WinGetVersion.Text = "WinGet Version: $Script:WINGET_VERSION"
    $Controls.InstallLocationText.Text = "Install Location: $($updatedConfig.InstallLocation) | "
    if ($wauGPOListPathEnabled -and $wauActivateGPOManagementEnabled) {
        $Controls.LocalListText.Inlines.Clear()
        $Controls.LocalListText.Inlines.Add("Local List: ")
        if ($updatedPolicies.WAU_UseWhiteList -eq 1) {
            $run = New-Object System.Windows.Documents.Run("'GPO (Included Apps)'")
        } else {
            $run = New-Object System.Windows.Documents.Run("'GPO (Excluded Apps)'")
        }   
        $run.Foreground = $Script:COLOR_ENABLED
        $Controls.LocalListText.Inlines.Add($run)
    }
    else {
        try {
            $installdir = $updatedConfig.InstallLocation
            if ($updatedConfig.WAU_UseWhiteList -eq 1 -or ($updatedPolicies.WAU_UseWhiteList -eq 1 -and $wauActivateGPOManagementEnabled)) {
                $whiteListFile = Join-Path $installdir 'included_apps.txt'
                if (Test-Path $whiteListFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'included_apps.txt'")
                    $run.Foreground = $Script:COLOR_ENABLED
                    $Controls.LocalListText.Inlines.Add($run)
                } else {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Missing Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'included_apps.txt'")
                    $run.Foreground = $Script:COLOR_DISABLED
                    $Controls.LocalListText.Inlines.Add($run)
                }
            } else {
                $excludedFile = Join-Path $installdir 'excluded_apps.txt'
                $defaultExcludedFile = Join-Path $installdir 'config\default_excluded_apps.txt'
                if (Test-Path $excludedFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_ENABLED
                    $Controls.LocalListText.Inlines.Add($run)
                } elseif (Test-Path $defaultExcludedFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'config\default_excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_ACTIVE
                    $Controls.LocalListText.Inlines.Add($run)
                } else {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Missing Local Lists: ")
                    $run = New-Object System.Windows.Documents.Run("'excluded_apps.txt' and 'config\default_excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_DISABLED
                    $Controls.LocalListText.Inlines.Add($run)
                }
            }
        }
        catch {
            $Controls.LocalListText.Inlines.Clear()
            $Controls.LocalListText.Inlines.Add("Local List: ")
            $run = New-Object System.Windows.Documents.Run("'Unknown'")
            $run.Foreground = $Script:COLOR_INACTIVE
            $Controls.LocalListText.Inlines.Add($run)
        }
    }

    # Update WAU AutoUpdate status
    $wauAutoUpdateDisabled = [bool](Get-DisplayValue -PropertyName "WAU_DisableAutoUpdate" -Config $updatedConfig -Policies $updatedPolicies)
    $wauPreReleaseEnabled = [bool](Get-DisplayValue -PropertyName "WAU_UpdatePrerelease" -Config $updatedConfig -Policies $updatedPolicies)
    $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
    $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)

    # Helper function to colorize status text
    function Get-ColoredStatusText($label, $enabled, $enabledText = "Enabled", $disabledText = "Disabled") {
        $color = if ($enabled) { $Script:COLOR_ENABLED } else { $Script:COLOR_DISABLED }
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

    # Check if we're being called from a save operation by checking if we're in GPO mode
    $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
    $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)
    $gpoControlsActive = $wauActivateGPOManagementEnabled -and $wauRunGPOManagementEnabled
    
    # Only show popup when window first opens, not when updating after save
    $skipPopupForInitialLoad = $false
    
    # Update GPO management state
    Update-GPOManagementState -Controls $controls -skipPopup $skipPopupForInitialLoad

    # Close the initial "Gathering Data..." popup if it's still open
    # ONLY do this if we're not in GPO mode (to avoid interfering with GPO popup)
    if (-not $gpoControlsActive) {
        try {
            if ($null -ne $Script:PopUpWindow) {
                Close-PopUp
            }
        }
        catch {
            # Popup might already be closed
        }
    }
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
        } else {
            Close-PopUp
            [System.Windows.MessageBox]::Show("WAU scheduled task not found!", "Error", "OK", "Error")
        }
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to start WAU: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}

# 6. GUI function (depends on most others)
function Show-WAUSettingsGUI {
    
    # Get current configuration
    $currentConfig = Get-WAUCurrentConfig
    
    # Load XAML
    [xml]$xamlXML = $Script:WINDOW_XAML -replace 'x:N', 'N'
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

    # Hyperlink event handlers
    $controls.ManifestsLink.Add_RequestNavigate({
        param($linkSource, $navEventArgs)
        try {
            Start-Process $navEventArgs.Uri.AbsoluteUri
            $navEventArgs.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.IssuesLink.Add_RequestNavigate({
        param($linkSource, $navEventArgs)
        try {
            Start-Process $navEventArgs.Uri.AbsoluteUri
            $navEventArgs.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # Dev button event handlers
    $controls.DevTaskButton.Add_Click({
        try {
            Start-PopUp "Task Scheduler opening, look in WAU folder..."
            # Open Task Scheduler
            $taskschdPath = "$env:SystemRoot\system32\taskschd.msc"
            Start-Process $taskschdPath

            # Update status to "Done"
            $controls.StatusBarText.Text = "Done"
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open Task Scheduler: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevRegButton.Add_Click({
        try {
            Start-PopUp "WAU Registry opening..."
            # Open Registry Editor and navigate to WAU registry key
            $regPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Romanitho\Winget-AutoUpdate"
            
            # Set the LastKey registry value to navigate to the desired location
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $regPath -Force
            
            # Open Registry Editor (it will open at the last key location)
            Start-Process "regedit.exe"
            
            # Update status to "Done"
            $controls.StatusBarText.Text = "Done"
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open Registry Editor: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevGUIDButton.Add_Click({
        try {
            Start-PopUp "WAU GUID Paths opening..."
            # Open Registry Editor and navigate to WAU Installation GUID registry key
            $GUIDPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${Script:WAU_GUID}"
	    
            # Set the LastKey registry value to navigate to the desired location
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $GUIDPath -Force
            
            # Open Registry Editor (it will open at the last key location)
            Start-Process "regedit.exe"

            Start-Process "explorer.exe" -ArgumentList "${env:SystemRoot}\Installer\${Script:WAU_GUID}"

            # Update status to "Done"
            $controls.StatusBarText.Text = "Done"
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open GUID Paths: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevListButton.Add_Click({
        try {
            # Get updated config and policies
            $updatedConfig = Get-WAUCurrentConfig
            $updatedPolicies = $null
            try {
                $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
            }
            catch {
                # GPO registry key doesn't exist or can't be read
            }
            $installdir = $updatedConfig.InstallLocation
            if ($updatedConfig.WAU_UseWhiteList -eq 1 -or $updatedPolicies.WAU_UseWhiteList -eq 1) {
                $whiteListFile = Join-Path $installdir 'included_apps.txt'
                if (Test-Path $whiteListFile) {
                    Start-PopUp "WAU Included Apps List opening..."
                    Start-Process "explorer.exe" -ArgumentList $whiteListFile
                } else {
                    [System.Windows.MessageBox]::Show("No Included Apps List found ('included_apps.txt')", "File Not Found", "OK", "Warning")
                    return
                }
            } else {
                $excludedFile = Join-Path $installdir 'excluded_apps.txt'
                $defaultExcludedFile = Join-Path $installdir 'config\default_excluded_apps.txt'
                if (Test-Path $excludedFile) {
                    Start-PopUp "WAU Excluded Apps List opening..."
                    Start-Process "explorer.exe" -ArgumentList $excludedFile
                } elseif (Test-Path $defaultExcludedFile) {
                    Start-PopUp "WAU Default Excluded Apps List opening..."
                    Start-Process "explorer.exe" -ArgumentList $defaultExcludedFile
                } else {
                    [System.Windows.MessageBox]::Show("No Excluded Apps List found (neither 'excluded_apps.txt' nor 'config\default_excluded_apps.txt').", "File Not Found", "OK", "Warning")
                    return
                }
            }

            # Update status to "Done"
            $controls.StatusBarText.Text = "Done"
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open List: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # Event handlers for controls
    $controls.SaveButton.Add_Click({
        # Check if settings are controlled by GPO
        $updatedConfig = Get-WAUCurrentConfig
        $updatedPolicies = $null
        try {
            $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
        }
        catch {
            # GPO registry key doesn't exist or can't be read
        }

        $wauActivateGPOManagementEnabled = ($updatedPolicies.WAU_ActivateGPOManagement -eq 1)
        $wauRunGPOManagementEnabled = ($updatedConfig.WAU_RunGPOManagement -eq 1)
        
        if ($wauActivateGPOManagementEnabled -and $wauRunGPOManagementEnabled) {
            # For GPO mode - show popup immediately without delay
            Start-PopUp "Saving WAU settings..."
            # Update status to "Saving settings"
            $controls.StatusBarText.Text = "Saving settings..."
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE

            # Only allow saving shortcut settings
            $newSettings = @{
                WAU_AppInstallerShortcut = if ($controls.AppInstallerShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_DesktopShortcut = if ($controls.DesktopShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_StartMenuShortcut = if ($controls.StartMenuShortcutCheckBox.IsChecked) { 1 } else { 0 }
            }
            
            # Save settings and close popup after a short delay
            if (Set-WAUConfig -Settings $newSettings) {
                # Close popup after default wait time and update GUI
                $controls.StatusBarText.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                    Start-Sleep -Milliseconds $Script:WAIT_TIME
                    # Update status to "Done"
                    $controls.StatusBarText.Text = "Done"
                    $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                    Close-PopUp
                    
                    # Update GUI settings
                    $updatedConfigAfterSave = Get-WAUCurrentConfig

                    # Update only the shortcut checkboxes since that's all we saved
                    $controls.AppInstallerShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_AppInstallerShortcut -eq 1)
                    $controls.DesktopShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_DesktopShortcut -eq 1)
                    $controls.StartMenuShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_StartMenuShortcut -eq 1)
                    
                    # Update GPO management state but SKIP the popup since we're updating after save
                    Update-GPOManagementState -Controls $controls -skipPopup $true
                }) | Out-Null
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Failed to save settings.", "Error", "OK", "Error")
            }
        } else {
            Start-PopUp "Saving WAU settings..."
            # Update status to "Saving settings"
            $controls.StatusBarText.Text = "Saving settings..."
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE
            
            # Force UI update
            [System.Windows.Forms.Application]::DoEvents()
            
            # Validate time format
            try {
                [datetime]::ParseExact($controls.UpdateTimeTextBox.Text, "HH:mm:ss", $null) | Out-Null
            }
            catch {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Invalid time format. Please use HH:mm:ss format (e.g., 06:00:00)", "Error", "OK", "Error")
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                return
            }
            
            # Validate random delay format
            try {
                [datetime]::ParseExact($controls.RandomDelayTextBox.Text, "HH:mm", $null) | Out-Null
            }
            catch {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Invalid time format. Please use HH:mm format (e.g., 00:00)", "Error", "OK", "Error")
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
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
                # Update status to "Done"
                $controls.StatusBarText.Text = "Done"
                $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                
                # Update GUI settings without popup (skip popup for normal mode too when updating after save)
                Update-WAUGUIFromConfig -Controls $controls
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Failed to save settings.", "Error", "OK", "Error")
            }
        }
        # Create timer to reset status back to ready after half standard wait time
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
        }) | Out-Null
    })

    # Cancel button handler to close window
    $controls.CancelButton.Add_Click({
        $controls.StatusBarText.Text = "Done"
        $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
        
        # Create timer to reset status and close window after 1 seconds
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Add_Tick({
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
            if ($null -ne $timer) {
                $timer.Stop()
            }
            $window.Close()
        })
        $timer.Start()
    })
    
    $controls.RunNowButton.Add_Click({
        Start-PopUp "WAU Update task starting..."
        Start-WAUManually
        # Update status to "Done"
        $controls.StatusBarText.Text = "Done"
        $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
        
        # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after standard wait time
        # Use Invoke-Async to avoid blocking
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds $Script:WAIT_TIME
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
            Close-PopUp
        }) | Out-Null
    })

    # Handle Enter key to save settings
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq 'Return' -or $_.Key -eq 'Enter') {
            $controls.SaveButton.RaiseEvent([Windows.RoutedEventArgs][Windows.Controls.Primitives.ButtonBase]::ClickEvent)
            $_.Handled = $true
        }
        # F12 key handler to toggle dev buttons visibility
        elseif ($_.Key -eq 'F12') {
            if ($controls.DevTaskButton.Visibility -eq 'Collapsed') {
                $controls.DevTaskButton.Visibility = 'Visible'
                $controls.DevRegButton.Visibility = 'Visible'
                $controls.DevGUIDButton.Visibility = 'Visible'
                $controls.DevListButton.Visibility = 'Visible'
                $controls.LinksStackPanel.Visibility = 'Visible'
                $window.Title = "$Script:WAU_TITLE - Dev Tools"
            } else {
                $controls.DevTaskButton.Visibility = 'Collapsed'
                $controls.DevRegButton.Visibility = 'Collapsed'
                $controls.DevGUIDButton.Visibility = 'Collapsed'
                $controls.DevListButton.Visibility = 'Collapsed'
                $controls.LinksStackPanel.Visibility = 'Collapsed'
                $window.Title = "$Script:WAU_TITLE"
            }
            $_.Handled = $true
        }        
    })

    # ESC key handler to close window
    $window.Add_KeyDown({
        if ($_.Key -eq "Escape") {
            $controls.StatusBarText.Text = "Done"
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status and close window after 1 seconds
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(1)
            $timer.Add_Tick({
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                if ($null -ne $timer) {
                    $timer.Stop()
                }
                $window.Close()
            })
            $timer.Start()
        }
    })
    
    $controls.OpenLogsButton.Add_Click({
        try {
            Start-PopUp "WAU Log directory opening..."
            $logPath = Join-Path $currentConfig.InstallLocation "logs"
            if (Test-Path $logPath) {
                Start-Process "explorer.exe" -ArgumentList $logPath
                # Update status to "Done"
                $controls.StatusBarText.Text = "Done"
                $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                
                # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after standard wait time
                # Use Invoke-Async to avoid blocking
                $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                    Start-Sleep -Milliseconds $Script:WAIT_TIME
                    $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                    $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                    Close-PopUp
                }) | Out-Null
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Log directory not found: $logPath", "Error", "OK", "Error")
            }
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open logs: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    Close-PopUp

    # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after STANDARD wait time
    # Use Invoke-Async to avoid blocking
    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        Start-Sleep -Milliseconds $Script:WAIT_TIME
        $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
        $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"

   }) | Out-Null
    
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

# Load icon from config file
$iconConfigPath = Join-Path $Script:WorkingDir "config\icon.txt"
if (Test-Path $iconConfigPath) {
    $Script:IconBase64 = [Convert]::FromBase64String((Get-Content $iconConfigPath -Raw).Trim())
} else {
    # Fallback to default or show error
    Write-Warning "Icon config file not found: $iconConfigPath"
    $Script:IconBase64 = $null
}

# Load PopUp XAML from config file and store as constant
$xamlConfigPath = Join-Path $Script:WorkingDir "config\settings-popup.xaml"
if (Test-Path $xamlConfigPath) {
    $inputXML = Get-Content $xamlConfigPath -Raw
    
    # Replace PowerShell variables with actual values
    $inputXML = $inputXML -replace '\$Script:WAU_TITLE', $Script:WAU_TITLE
    $Script:POPUP_XAML = $inputXML.Trim()
} else {
    [System.Windows.MessageBox]::Show("PopUp XAML config file not found: $xamlConfigPath", "$Script:WAU_TITLE", "OK", "Warning")
    exit 1
}

# Load Window XAML from config file and store as constant
$xamlConfigPath = Join-Path $Script:WorkingDir "config\settings-window.xaml"
if (Test-Path $xamlConfigPath) {
    $inputXML = Get-Content $xamlConfigPath -Raw
    
    # Replace PowerShell variables with actual values
    $inputXML = $inputXML -replace '\$Script:WAU_TITLE', $Script:WAU_TITLE
    $inputXML = $inputXML -replace '\$Script:COLOR_ENABLED', $Script:COLOR_ENABLED
    $inputXML = $inputXML -replace '\$Script:COLOR_DISABLED', $Script:COLOR_DISABLED
    $inputXML = $inputXML -replace '\$Script:COLOR_ACTIVE', $Script:COLOR_ACTIVE
    $inputXML = $inputXML -replace '\$Script:COLOR_INACTIVE', $Script:COLOR_INACTIVE
    $inputXML = $inputXML -replace '\$Script:STATUS_READY_TEXT', $Script:STATUS_READY_TEXT
    $Script:WINDOW_XAML = $inputXML.Trim()
} else {
    [System.Windows.MessageBox]::Show("Window XAML config file not found: $xamlConfigPath", "$Script:WAU_TITLE", "OK", "Warning")
    exit 1
}

#Pop "Starting..."
Start-PopUp "Gathering Data..."

# Get WAU installation info once and store as constants
$Script:WAU_INSTALL_INFO = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
$Script:WAU_VERSION = if ($Script:WAU_INSTALL_INFO.Count -ge 1) { $Script:WAU_INSTALL_INFO[0] } else { "Unknown" }
# Get WinGet version by running 'winget -v'
try {
    $wingetVersionOutput = winget -v 2>$null
    $Script:WINGET_VERSION = $wingetVersionOutput.Trim().TrimStart("v")
} catch {
    $Script:WINGET_VERSION = "Unknown"
}
$Script:WAU_GUID = if ($Script:WAU_INSTALL_INFO.Count -ge 2) { $Script:WAU_INSTALL_INFO[1] } else { $null }
$Script:WAU_ICON = "${env:SystemRoot}\Installer\${Script:WAU_GUID}\icon.ico"

# Show the GUI
Show-WAUSettingsGUI
