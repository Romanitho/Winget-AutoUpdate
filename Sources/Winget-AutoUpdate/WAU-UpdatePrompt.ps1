<#
.SYNOPSIS
    Displays the WAU update deadline prompt dialog to the logged-in user.

.DESCRIPTION
    Runs as SYSTEM in the logged-in user's desktop session via ServiceUI.exe.
    Reads pending-updates.json written by the main WAU task and presents a WPF
    dialog listing apps with pending deadlines.

    User actions:
        "Update Now"            -- fires Winget-AutoUpdate-UpdateNow task for all apps
        "Update Selected (N)"   -- rewrites JSON with selected apps only, fires task, reminds for the rest
        "Remind Me in X Days"   -- writes NextPromptTime to HKLM, then exits

    The X button is blocked to prevent users from thinking they are circumventing
    the system. A hidden auto-dismiss timer closes the dialog at
    (ReminderIntervalDays - 1 hour) without writing NextPromptTime, so the next
    WAU run will re-prompt with fresh data.

    Must be launched with PowerShell -Sta flag (STA apartment model required for WPF).

.NOTES
    Scheduled task:  Winget-AutoUpdate-UpdatePrompt
    Run as:          SYSTEM (S-1-5-18), RunLevel Highest
    Launch command:  ServiceUI.exe -process:explorer.exe
                         powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta
                         -WindowStyle Hidden -EncodedCommand <base64>
    Trigger:         On demand (started by Start-UpdatePromptTask.ps1)
    Instances:       IgnoreNew
#>

#Requires -Version 5.1

#region ASSEMBLIES
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
#endregion ASSEMBLIES

#region ROW DATA CLASS
# A proper CLR class is required for reliable WPF data binding.
# PSCustomObject NoteProperties are not guaranteed to be discoverable
# by WPF's PropertyDescriptor mechanism used by DisplayMemberBinding
# and DataTrigger value comparison.
Add-Type -TypeDefinition @'
public class WauAppRow {
    public bool   IsSelected           { get; set; }
    public string Id                   { get; set; }
    public string Name                 { get; set; }
    public string AvailableVersion     { get; set; }
    public string DeadlineDisplay      { get; set; }
    public string DaysRemainingDisplay { get; set; }
    public int    DaysRemainingValue   { get; set; }
    public bool   IsUrgent             { get; set; }
    public bool   IsFinalDay           { get; set; }
}
'@
#endregion ROW DATA CLASS

#region READ PENDING UPDATES
$JsonPath = [System.IO.Path]::Combine($PSScriptRoot, 'config', 'pending-updates.json')

if (-not (Test-Path $JsonPath)) {
    Exit 0
}

try {
    $pendingData = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Exit 1
}

if (-not $pendingData.Apps -or @($pendingData.Apps).Count -eq 0) {
    Exit 0
}

$reminderDays = 2
if ($pendingData.Config -and $null -ne $pendingData.Config.ReminderIntervalDays) {
    $parsedReminderDays = 0
    if ([int]::TryParse([string]$pendingData.Config.ReminderIntervalDays, [ref]$parsedReminderDays) -and $parsedReminderDays -ge 1) {
        $reminderDays = $parsedReminderDays
    }
}
$companyName = ''
if ($pendingData.Config -and $pendingData.Config.CompanyName) {
    $companyName = $pendingData.Config.CompanyName
}
#endregion READ PENDING UPDATES

#region BUILD ROW OBJECTS
$today   = (Get-Date).Date
$appRows = [System.Collections.Generic.List[WauAppRow]]::new()

foreach ($app in @($pendingData.Apps)) {
    $deadline = $null
    try {
        if ([string]::IsNullOrWhiteSpace($app.Deadline)) { continue }
        $deadline = [DateTime]::ParseExact($app.Deadline, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch { continue }

    $daysLeft = ($deadline - $today).Days

    $row = [WauAppRow]::new()
    $row.IsSelected           = ($daysLeft -le 0)
    $row.Id                   = $app.Id
    $row.Name                 = $app.Name
    $row.AvailableVersion     = $app.AvailableVersion
    $row.DeadlineDisplay      = $deadline.ToString('MMM d, yyyy')
    $row.DaysRemainingDisplay = switch ($daysLeft) {
        { $_ -lt 0 } { 'Overdue' }
        0             { 'Today' }
        1             { '1 day' }
        default       { "$daysLeft days" }
    }
    $row.DaysRemainingValue   = $daysLeft
    $row.IsUrgent             = ($daysLeft -le 3)
    $row.IsFinalDay           = ($daysLeft -le 0)

    $appRows.Add($row)
}

# Sort ascending so most urgent apps appear at the top
$sortedRows = @($appRows | Sort-Object DaysRemainingValue)
$script:HasFinalDayApps = @($sortedRows | Where-Object { $_.IsFinalDay }).Count -gt 0
$script:AllFinalDay     = @($sortedRows | Where-Object { -not $_.IsFinalDay }).Count -eq 0
#endregion BUILD ROW OBJECTS

#region XAML
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Software Update Required"
    Width="660"
    SizeToContent="Height"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterScreen"
    Topmost="True"
    Background="#F3F3F3">

    <Grid Margin="24,20,24,20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <TextBlock Grid.Row="0"
                   Name="HeaderText"
                   TextWrapping="Wrap"
                   FontSize="13"
                   FontWeight="SemiBold"
                   Margin="0,0,0,6"/>

        <!-- Instruction -->
        <TextBlock Grid.Row="1"
                   Name="InstructionText"
                   TextWrapping="Wrap"
                   FontSize="11"
                   Foreground="#444444"
                   Margin="0,0,0,14"/>

        <!-- App list -->
        <ListView Grid.Row="2"
                  Name="AppList"
                  MaxHeight="280"
                  Margin="0,0,0,12"
                  BorderBrush="#CCCCCC"
                  BorderThickness="1"
                  Background="White"
                  ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListView.View>
                <GridView>
                    <GridViewColumn Width="30">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}"
                                          HorizontalAlignment="Center"
                                          VerticalAlignment="Center">
                                    <CheckBox.Style>
                                        <Style TargetType="CheckBox">
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding IsFinalDay}" Value="True">
                                                    <Setter Property="IsEnabled" Value="False"/>
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </CheckBox.Style>
                                </CheckBox>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Application"
                                    Width="190"
                                    DisplayMemberBinding="{Binding Name}"/>
                    <GridViewColumn Header="Available Version"
                                    Width="120"
                                    DisplayMemberBinding="{Binding AvailableVersion}"/>
                    <GridViewColumn Header="Required By"
                                    Width="100"
                                    DisplayMemberBinding="{Binding DeadlineDisplay}"/>
                    <GridViewColumn Header="Days Remaining"
                                    Width="110"
                                    DisplayMemberBinding="{Binding DaysRemainingDisplay}"/>
                </GridView>
            </ListView.View>
            <ListView.ItemContainerStyle>
                <Style TargetType="ListViewItem">
                    <Setter Property="Focusable" Value="False"/>
                    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                    <Style.Triggers>
                        <DataTrigger Binding="{Binding IsUrgent}" Value="True">
                            <Setter Property="Background" Value="#FFF3CD"/>
                            <Setter Property="BorderBrush" Value="#FFE69C"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding IsFinalDay}" Value="True">
                            <Setter Property="Background" Value="#FFA5A5"/>
                            <Setter Property="BorderBrush" Value="#FF8A8A"/>
                        </DataTrigger>
                    </Style.Triggers>
                </Style>
            </ListView.ItemContainerStyle>
        </ListView>

        <!-- Footer -->
        <TextBlock Grid.Row="3"
                   Text="Updates will run in the background and restart affected applications if necessary."
                   TextWrapping="Wrap"
                   FontSize="11"
                   Foreground="#666666"
                   Margin="0,0,0,16"/>

        <!-- Action buttons -->
        <StackPanel Grid.Row="4"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right">
            <Button Name="RemindButton"
                    Height="30"
                    Margin="0,0,10,0"
                    FontSize="12"
                    Padding="16,0"/>
            <Button Name="UpdateNowButton"
                    Content="Update Now"
                    Height="30"
                    FontSize="12"
                    FontWeight="SemiBold"
                    IsDefault="True"
                    Padding="16,0"/>
        </StackPanel>

    </Grid>
</Window>
'@
#endregion XAML

#region WINDOW SETUP
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$appListCtrl    = $window.FindName('AppList')
$remindBtn      = $window.FindName('RemindButton')
$updateNowBtn   = $window.FindName('UpdateNowButton')
$headerTxt      = $window.FindName('HeaderText')
$instructionTxt = $window.FindName('InstructionText')

# Set header text with company name if configured
if ($companyName) {
    $headerTxt.Text = "$companyName requires the following updates to be installed."
}
else {
    $headerTxt.Text = "Your organization requires the following updates to be installed."
}

# Set instruction text and button visibility based on final-day apps
$dayLabel = if ($reminderDays -ne 1) { 'days' } else { 'day' }
if ($script:AllFinalDay) {
    $instructionTxt.Text = "The following apps have reached their update deadline and must be updated now."
    $remindBtn.Visibility = [System.Windows.Visibility]::Collapsed
}
elseif ($script:HasFinalDayApps) {
    $instructionTxt.Text = "Apps highlighted in red have reached their deadline and must be updated today. You may select additional apps to include in this update."
    $remindBtn.Visibility = [System.Windows.Visibility]::Collapsed
}
else {
    $instructionTxt.Text = "Check the box next to apps you're ready to update now, or update all at once. If you don't update all apps now, you will be reminded in $reminderDays $dayLabel."
}

# Set window icon from WAU's notify_icon.png if available
$iconPath = Join-Path $PSScriptRoot 'icons\notify_icon.png'
if (Test-Path $iconPath) {
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
    $bitmap.EndInit()
    $window.Icon = $bitmap
}

# Set button label with configured interval
$remindBtn.Content = "Remind Me in $reminderDays $dayLabel"

# Populate the ListView
$appListCtrl.ItemsSource = $sortedRows
#endregion WINDOW SETUP

#region INTERACTION LOGIC
# Tracks the user's chosen action. Defaults to Remind for safety.
$script:Action     = 'Remind'
$script:AllowClose = $false

# Block the X button -- users must choose Remind or Update.
# Button handlers set AllowClose before calling Close().
$window.Add_Closing({
    param($eventSender, $e)
    if (-not $script:AllowClose) {
        $e.Cancel = $true
    }
})

# Hidden auto-dismiss timer: closes the dialog at (ReminderIntervalDays - 1 hour)
# without writing NextPromptTime, so the next WAU run will re-prompt with fresh data.
# Uses wall-clock comparison every 5 minutes to survive sleep/wake cycles.
$dismissTime = [DateTime]::Now.AddDays($reminderDays).AddHours(-1)

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(5)
$timer.Add_Tick({
    if ([DateTime]::Now -ge $dismissTime) {
        $timer.Stop()
        $script:AllowClose = $true
        $script:Action = 'SilentDismiss'
        $window.Close()
    }
})
$timer.Start()

# Checkbox state tracking -- update button text and Remind availability
# when any checkbox in the ListView is toggled.
$script:UpdateButtonState = {
    $selectedCount = @($sortedRows | Where-Object { $_.IsSelected }).Count
    if ($selectedCount -eq 0) {
        $updateNowBtn.Content = 'Update Now'
        $remindBtn.IsEnabled = $true
    }
    elseif ($selectedCount -eq $sortedRows.Count) {
        $updateNowBtn.Content = 'Update Now'
        $remindBtn.IsEnabled = $false
    }
    else {
        $updateNowBtn.Content = "Update Selected ($selectedCount)"
        $remindBtn.IsEnabled = $false
    }
}

# Set initial button state (final-day apps start pre-checked)
& $script:UpdateButtonState

$appListCtrl.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
    [System.Windows.RoutedEventHandler]{ & $script:UpdateButtonState }
)
$appListCtrl.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
    [System.Windows.RoutedEventHandler]{ & $script:UpdateButtonState }
)

$updateNowBtn.Add_Click({
    $timer.Stop()
    $script:AllowClose = $true
    $script:Action = 'UpdateNow'
    $window.Close()
})

$remindBtn.Add_Click({
    $timer.Stop()
    $script:AllowClose = $true
    $script:Action = 'Remind'
    $window.Close()
})

$window.ShowDialog() | Out-Null
#endregion INTERACTION LOGIC

#region ACT ON CHOICE
$WAURegPath = 'HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate'

if ($script:Action -eq 'UpdateNow') {
    $selectedApps = @($sortedRows | Where-Object { $_.IsSelected })

    # Partial update: some (but not all) apps selected via checkboxes.
    # Rewrite pending-updates.json with only selected apps so UpdateNow
    # processes just those. Write NextPromptTime for the remainder.
    if ($selectedApps.Count -gt 0 -and $selectedApps.Count -lt $sortedRows.Count) {
        $selectedIds  = @($selectedApps | ForEach-Object { $_.Id })
        $filteredApps = @($pendingData.Apps | Where-Object { $_.Id -in $selectedIds })

        $jsonOut = [ordered]@{
            Config = $pendingData.Config
            Apps   = $filteredApps
        }
        $jsonOut | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8 -Force

        # Remind for unselected apps
        $nextPromptTime = (Get-Date).AddDays($reminderDays).ToString('o')
        try {
            Set-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -Value $nextPromptTime
        }
        catch { }
    }
    else {
        # Full update: rewrite pending-updates.json from in-memory data to guard against
        # a race where the main SYSTEM cycle overwrites the file while the prompt is open.
        $jsonOut = [ordered]@{
            Config = $pendingData.Config
            Apps   = $pendingData.Apps
        }
        $jsonOut | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonPath -Encoding UTF8 -Force

        # Clear any stale NextPromptTime from a previous partial snooze
        Remove-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -ErrorAction SilentlyContinue
    }

    # Fire the UpdateNow task
    $updateTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UpdateNow' -ErrorAction SilentlyContinue
    if ($updateTask) {
        $updateTask | Start-ScheduledTask
    }
}
elseif ($script:Action -eq 'Remind') {
    # Snooze -- record when the next prompt is allowed so the main
    # SYSTEM task skips the prompt until this time has passed.
    $nextPromptTime = (Get-Date).AddDays($reminderDays).ToString('o')
    try {
        Set-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -Value $nextPromptTime
    }
    catch { }
}
# SilentDismiss: no action taken, no NextPromptTime written.
# Next WAU run will re-prompt with fresh data.
#endregion ACT ON CHOICE
