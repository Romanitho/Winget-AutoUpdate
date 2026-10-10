<#
.SYNOPSIS
    Displays the modern WAU update deadline prompt dialog to the logged-in user.

.DESCRIPTION
    Runs as SYSTEM in the logged-in user's desktop session via ServiceUI.exe.
    Reads pending-updates.json written by the main WAU task and presents a modern
    WPF Fluent Design dialog listing apps with pending deadlines.

    Features:
        - Modern Windows 11 / Fluent aesthetics (rounded cards, pill badges, clean typography)
        - Native Dark Mode auto-detection matching Windows system / user theme settings
        - DWM Immersive Dark Mode title bar integration (Windows 10 1809+ and Windows 11)
        - Clean pill badges for "Time Remaining" with contextual colors (Overdue, Urgent, Pending)
        - Branded icon in header card (with vector icon fallback)
        - Polished Primary ("Update Now") and Secondary ("Remind Me") action buttons

    User actions:
        "Update Now"            -- fires Winget-AutoUpdate-UpdateNow task for all apps
        "Update Selected (N)"   -- rewrites JSON with selected apps only, fires task, reminds for the rest
        "Remind Me in X Hours"  -- writes NextPromptTime to HKLM, then exits

    The X button is blocked to prevent users from thinking they are circumventing
    the system. A hidden auto-dismiss timer closes the dialog shortly before the
    configured reminder interval without writing NextPromptTime, so the next
    WAU run will re-prompt with fresh data.

    Must be launched with PowerShell -Sta flag (STA apartment model required for WPF).

.NOTES
    Scheduled task:  Winget-AutoUpdate-UpdatePrompt
    Run as:          SYSTEM (S-1-5-18), RunLevel Highest
    Launch command:  WAU-LaunchUpdatePrompt.ps1 -> ServiceUI.exe -session:<id>
                         powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta
                         -WindowStyle Hidden -EncodedCommand <base64>
    Trigger:         On demand (started by Start-UpdatePromptTask.ps1)
    Instances:       IgnoreNew
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DarkMode,
    [switch]$LightMode
)

#region ASSEMBLIES
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
#endregion ASSEMBLIES

#region THEME HELPER & DATA CLASSES
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WauAppRow {
    public bool   IsSelected           { get; set; }
    public string Id                   { get; set; }
    public string Key                  { get; set; }
    public string ScopeDisplay         { get; set; }
    public bool CanUpdate              { get; set; }
    public string Name                 { get; set; }
    public string AvailableVersion     { get; set; }
    public string DeadlineDisplay      { get; set; }
    public string DaysRemainingDisplay { get; set; }
    public double DaysRemainingValue   { get; set; }
    public bool   IsUrgent             { get; set; }
    public bool   IsFinalDay           { get; set; }
    public string BadgeBackground      { get; set; }
    public string BadgeForeground      { get; set; }
    public string BadgeBorder          { get; set; }
    public string RowBackground        { get; set; }
    public string RowBorder            { get; set; }
    public string BlockReason          { get; set; }
    public string BlockTooltip         { get; set; }
}

public class NativeThemeHelper {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void SetDarkMode(IntPtr hwnd, bool enabled) {
        try {
            int useDark = enabled ? 1 : 0;
            // DWMWA_USE_IMMERSIVE_DARK_MODE (20 on Win11/Win10 20H1+, 19 on older Win10)
            if (DwmSetWindowAttribute(hwnd, 20, ref useDark, sizeof(int)) != 0) {
                DwmSetWindowAttribute(hwnd, 19, ref useDark, sizeof(int));
            }
        } catch { }
    }
}
'@
#endregion THEME HELPER & DATA CLASSES

#region DARK MODE DETECTION
function Get-IsDarkMode {
    <#
    .SYNOPSIS
        Detects if Windows is configured to use Dark Mode for applications.
    .DESCRIPTION
        Checks HKCU first. If running as SYSTEM (ServiceUI.exe), inspects
        active interactive user registry hives under HKEY_USERS.
    #>
    # 1. Try HKCU (current user session)
    try {
        $regVal = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
        if ($null -ne $regVal) {
            return ($regVal -eq 0)
        }
    } catch {}

    # 2. Check active user profiles under HKEY_USERS (for SYSTEM / ServiceUI context)
    try {
        $userSids = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-\d+(-\d+)+$' }
        foreach ($sid in $userSids) {
            $path = "Registry::HKEY_USERS\$($sid.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            if (Test-Path $path) {
                $val = (Get-ItemProperty -Path $path -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
                if ($null -ne $val) {
                    return ($val -eq 0)
                }
            }
        }
    } catch {}

    # 3. Fallback to SystemUsesLightTheme if AppsUseLightTheme is not set
    try {
        $sysVal = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -ErrorAction SilentlyContinue).SystemUsesLightTheme
        if ($null -ne $sysVal) {
            return ($sysVal -eq 0)
        }
    } catch {}

    return $false
}

$isDarkMode = if ($DarkMode) { $true } elseif ($LightMode) { $false } else { Get-IsDarkMode }
#endregion DARK MODE DETECTION

#region READ PENDING UPDATES
$JsonPath = [System.IO.Path]::Combine($PSScriptRoot, 'config', 'pending-updates.json')
. "$PSScriptRoot\functions\Scope-Updates.ps1"
$Script:WorkingDir = $PSScriptRoot

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

$reminderHours = 2
if ($pendingData.Config) {
    if ($null -ne $pendingData.Config.ReminderIntervalHours) {
        $parsedReminderHours = 0
        if ([int]::TryParse([string]$pendingData.Config.ReminderIntervalHours, [ref]$parsedReminderHours) -and $parsedReminderHours -ge 1) {
            $reminderHours = $parsedReminderHours
        }
    }
    elseif ($null -ne $pendingData.Config.ReminderIntervalDays) {
        $parsedReminderDays = 0
        if ([int]::TryParse([string]$pendingData.Config.ReminderIntervalDays, [ref]$parsedReminderDays) -and $parsedReminderDays -ge 1) {
            $reminderHours = $parsedReminderDays * 24
        }
    }
}
$companyName = ''
if ($pendingData.Config -and $pendingData.Config.CompanyName) {
    $companyName = $pendingData.Config.CompanyName
}
#endregion READ PENDING UPDATES

#region BUILD ROW OBJECTS
# Do not show another session's user inventory or collect consent in that session.
if (-not $pendingData.Config.UserSid -or (Get-WauInteractiveUser) -ne $pendingData.Config.UserSid) { Exit 1 }
$now = Get-Date
$appRows = [System.Collections.Generic.List[WauAppRow]]::new()
[string[]]$dateFormats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd')

foreach ($app in @($pendingData.Apps)) {
    $deadline = $null
    try {
        if ([string]::IsNullOrWhiteSpace($app.Deadline)) { continue }
        $deadline = [DateTime]::ParseExact($app.Deadline, $dateFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
    } catch { continue }

    $timeSpan = $deadline - $now
    $hoursLeft = $timeSpan.TotalHours
    $minutesLeft = $timeSpan.TotalMinutes

    $row = [WauAppRow]::new()
    $row.CanUpdate        = $app.CanUpdate -eq $true
    $row.IsSelected       = ($hoursLeft -le 0 -and $row.CanUpdate -and -not $app.RequiresScopeMigration)
    $row.Id               = $app.Id
    $row.Key              = $app.Key
    $row.ScopeDisplay     = if ($app.Scope -eq 'user') { 'User' } else { 'Machine' }
    if ($app.RequiresScopeMigration) { $row.ScopeDisplay += ' -> Machine (consent required)' }
    if ($app.BlockReason) { $row.ScopeDisplay += " | $($app.BlockReason)" }
    if ($app.Version -eq 'Unknown') { $row.ScopeDisplay += ' | installed version unknown' }
    $row.Name             = $app.Name
    $row.AvailableVersion = $app.AvailableVersion
    $row.BlockReason      = if ($app.BlockReason) { [string]$app.BlockReason } else { '' }

    # DeadlineDisplay (Required By)
    if ($deadline.Date -eq $now.Date) {
        $row.DeadlineDisplay = "Today, $($deadline.ToString('HH:mm'))"
    }
    elseif ($deadline.Date -eq $now.Date.AddDays(1)) {
        $row.DeadlineDisplay = "Tomorrow, $($deadline.ToString('HH:mm'))"
    }
    else {
        $row.DeadlineDisplay = $deadline.ToString('MMM d, HH:mm')
    }

    # Time Remaining Display & Modern Badges
    if ($hoursLeft -le 0) {
        $row.DaysRemainingDisplay = 'Overdue'
        $row.BadgeBackground      = if ($isDarkMode) { '#450A0A' } else { '#FEE2E2' }
        $row.BadgeForeground      = if ($isDarkMode) { '#F87171' } else { '#DC2626' }
        $row.BadgeBorder          = if ($isDarkMode) { '#7F1D1D' } else { '#FCA5A5' }
        $row.RowBackground        = if ($isDarkMode) { '#2C1B1E' } else { '#FFF5F5' }
        $row.RowBorder            = if ($isDarkMode) { '#59222B' } else { '#FECACA' }
    }
    elseif ($hoursLeft -le 8.05) {
        # Workday deadline window (<= 8 hours, including default 8h deadline)
        $hrs = [int][math]::Ceiling($hoursLeft)
        $row.DaysRemainingDisplay = if ($hoursLeft -lt 1) {
            $mins = [math]::Max(1, [int][math]::Ceiling($minutesLeft))
            if ($mins -eq 1) { "1 min" } else { "$mins mins" }
        } else {
            if ($hrs -eq 1) { "1 hour" } else { "$hrs hours" }
        }
        $row.BadgeBackground      = '#ff4840'
        $row.BadgeForeground      = '#FFFFFF'
        $row.BadgeBorder          = '#E03A32'
        $row.RowBackground        = if ($isDarkMode) { '#2C1E20' } else { '#FFF5F5' }
        $row.RowBorder            = if ($isDarkMode) { '#592228' } else { '#FCA5A5' }
    }
    else {
        # Normal pending update (> 8 hours)
        if ($hoursLeft -lt 24) {
            $hrs = [int][math]::Ceiling($hoursLeft)
            $row.DaysRemainingDisplay = if ($hrs -eq 1) { "1 hour" } else { "$hrs hours" }
        } else {
            $days = [int][math]::Ceiling($timeSpan.TotalDays)
            $row.DaysRemainingDisplay = if ($days -eq 1) { "1 day" } else { "$days days" }
        }
        $row.BadgeBackground      = if ($isDarkMode) { '#283141' } else { '#F1F5F9' }
        $row.BadgeForeground      = if ($isDarkMode) { '#94A3B8' } else { '#475569' }
        $row.BadgeBorder          = if ($isDarkMode) { '#374357' } else { '#E2E8F0' }
        $row.RowBackground        = 'Transparent'
        $row.RowBorder            = if ($isDarkMode) { '#2D2D2D' } else { '#F3F4F6' }
    }

    $row.DaysRemainingValue = $hoursLeft
    $row.IsUrgent           = ($hoursLeft -le 8)
    $row.IsFinalDay         = ($hoursLeft -le 0 -and $row.CanUpdate -and -not $app.RequiresScopeMigration)
    if (-not $row.CanUpdate) {
        $deferUntilStr = if ($app.DeferUntil) {
            [string]$app.DeferUntil
        } elseif ($app.BlockReason -match 'until\s+([\d\-]+(\s+[\d\:]+)?)') {
            $matches[1]
        } else {
            $null
        }

        if ($deferUntilStr) {
            try {
                $deferDate = [DateTime]::ParseExact($deferUntilStr, @('yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss'), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
                if ($deferDate.Date -eq $now.Date) {
                    $row.DeadlineDisplay = "Until today, $($deferDate.ToString('HH:mm'))"
                } elseif ($deferDate.Date -eq $now.Date.AddDays(1)) {
                    $row.DeadlineDisplay = "Until tomorrow, $($deferDate.ToString('HH:mm'))"
                } else {
                    $row.DeadlineDisplay = "Until $($deferDate.ToString('MMM d, HH:mm'))"
                }
            } catch {
                $row.DeadlineDisplay = "Until $deferUntilStr"
            }
        } else {
            $row.DeadlineDisplay = '-'
        }

        $row.DaysRemainingDisplay = 'Blocked'
        $row.BadgeBackground = if ($isDarkMode) { '#283141' } else { '#F1F5F9' }
        $row.BadgeForeground = if ($isDarkMode) { '#94A3B8' } else { '#475569' }
        $row.BadgeBorder = if ($isDarkMode) { '#374357' } else { '#E2E8F0' }
        $row.RowBackground = 'Transparent'
        $row.RowBorder = if ($isDarkMode) { '#2D2D2D' } else { '#F3F4F6' }
        $row.IsUrgent = $false

        $tooltipLines = [System.Collections.Generic.List[string]]::new()
        if ($app.BlockReason)  { $tooltipLines.Add("Status: $($app.BlockReason)") }
        if ($deferUntilStr)    { $tooltipLines.Add("Deferred until: $deferUntilStr") }
        if ($app.ReleaseDate)  { $tooltipLines.Add("Released: $($app.ReleaseDate)") }
        if ($app.DeferralDays) { $tooltipLines.Add("Policy deferral: $($app.DeferralDays) days") }
        $row.BlockTooltip = $tooltipLines -join "`n"
    }

    $appRows.Add($row)
}

# Sort so non-blocked apps appear first (most urgent at the top), and blocked apps appear at the bottom
$sortedRows = @($appRows | Sort-Object `
    @{ Expression = { if ($_.CanUpdate) { 0 } else { 1 } } }, `
    @{ Expression = { $_.DaysRemainingValue } }, `
    @{ Expression = { $_.Name } }
)

# If no apps have deadlines, there is nothing to prompt for
if ($sortedRows.Count -eq 0) { Exit 0 }

$script:HasFinalDayApps = @($sortedRows | Where-Object { $_.IsFinalDay }).Count -gt 0
$updatableRows          = @($sortedRows | Where-Object CanUpdate)
$script:AllFinalDay     = $updatableRows.Count -gt 0 -and @($updatableRows | Where-Object { -not $_.IsFinalDay }).Count -eq 0
#endregion BUILD ROW OBJECTS

#region THEME COLOR TOKENS
if ($isDarkMode) {
    $t = @{
        WindowBg            = "#202020"
        HeaderCardBg        = "#292929"
        CardBorder          = "#383838"
        IconContainerBg     = "#333333"
        IconContainerBorder = "#444444"
        TextPrimary         = "#FFFFFF"
        TextSecondary       = "#CCCCCC"
        TextMuted           = "#949494"
        ListBg              = "#242424"
        ListBorder          = "#383838"
        ListHeaderBg        = "#2B2B2B"
        ListHeaderText      = "#AAAAAA"
        ListHeaderBorder    = "#383838"
        ListItemHover       = "#2F2F2F"
        PrimaryBtnBg        = "#0078D4"
        PrimaryBtnHover     = "#1A86D9"
        PrimaryBtnPressed   = "#006CBE"
        PrimaryBtnText      = "#FFFFFF"
        SecondaryBtnBg      = "#2D2D2D"
        SecondaryBtnHover   = "#383838"
        SecondaryBtnPressed = "#262626"
        SecondaryBtnBorder  = "#484848"
        SecondaryBtnText    = "#E0E0E0"
        CheckBoxBg          = "#2A2A2A"
        CheckBoxBorder      = "#6B7280"
    }
}
else {
    $t = @{
        WindowBg            = "#F3F3F3"
        HeaderCardBg        = "#FFFFFF"
        CardBorder          = "#E5E7EB"
        IconContainerBg     = "#F0F4F8"
        IconContainerBorder = "#D9E2EC"
        TextPrimary         = "#1A1A1A"
        TextSecondary       = "#525252"
        TextMuted           = "#71717A"
        ListBg              = "#FFFFFF"
        ListBorder          = "#E5E7EB"
        ListHeaderBg        = "#F8FAFC"
        ListHeaderText      = "#64748B"
        ListHeaderBorder    = "#E2E8F0"
        ListItemHover       = "#F1F5F9"
        PrimaryBtnBg        = "#0067C0"
        PrimaryBtnHover     = "#1975C5"
        PrimaryBtnPressed   = "#005BA1"
        PrimaryBtnText      = "#FFFFFF"
        SecondaryBtnBg      = "#FFFFFF"
        SecondaryBtnHover   = "#F4F4F5"
        SecondaryBtnPressed = "#E4E4E7"
        SecondaryBtnBorder  = "#D4D4D8"
        SecondaryBtnText    = "#18181B"
        CheckBoxBg          = "#FFFFFF"
        CheckBoxBorder      = "#9CA3AF"
    }
}
$accent = Get-WauAccentPalette -UserSid $pendingData.Config.UserSid
$t.PrimaryBtnBg = $accent.Base
$t.PrimaryBtnHover = $accent.Hover
$t.PrimaryBtnPressed = $accent.Pressed
$t.PrimaryBtnText = $accent.Text#endregion THEME COLOR TOKENS

#region XAML
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Software Update Required"
    Width="740"
    SizeToContent="Height"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterScreen"
    Topmost="True"
    FontFamily="Segoe UI Variable Display, Segoe UI, -apple-system, BlinkMacSystemFont, Roboto, sans-serif"
    Background="$($t.WindowBg)">

    <Window.Resources>
        <SolidColorBrush x:Key="Brush.WindowBg" Color="$($t.WindowBg)"/>
        <SolidColorBrush x:Key="Brush.HeaderCardBg" Color="$($t.HeaderCardBg)"/>
        <SolidColorBrush x:Key="Brush.CardBorder" Color="$($t.CardBorder)"/>
        <SolidColorBrush x:Key="Brush.IconContainerBg" Color="$($t.IconContainerBg)"/>
        <SolidColorBrush x:Key="Brush.IconContainerBorder" Color="$($t.IconContainerBorder)"/>
        <SolidColorBrush x:Key="Brush.TextPrimary" Color="$($t.TextPrimary)"/>
        <SolidColorBrush x:Key="Brush.TextSecondary" Color="$($t.TextSecondary)"/>
        <SolidColorBrush x:Key="Brush.TextMuted" Color="$($t.TextMuted)"/>
        <SolidColorBrush x:Key="Brush.ListBg" Color="$($t.ListBg)"/>
        <SolidColorBrush x:Key="Brush.ListBorder" Color="$($t.ListBorder)"/>
        <SolidColorBrush x:Key="Brush.ListHeaderBg" Color="$($t.ListHeaderBg)"/>
        <SolidColorBrush x:Key="Brush.ListHeaderText" Color="$($t.ListHeaderText)"/>
        <SolidColorBrush x:Key="Brush.ListHeaderBorder" Color="$($t.ListHeaderBorder)"/>
        <SolidColorBrush x:Key="Brush.ListItemHover" Color="$($t.ListItemHover)"/>
        <SolidColorBrush x:Key="Brush.PrimaryBtnBg" Color="$($t.PrimaryBtnBg)"/>
        <SolidColorBrush x:Key="Brush.PrimaryBtnHover" Color="$($t.PrimaryBtnHover)"/>
        <SolidColorBrush x:Key="Brush.PrimaryBtnPressed" Color="$($t.PrimaryBtnPressed)"/>
        <SolidColorBrush x:Key="Brush.PrimaryBtnText" Color="$($t.PrimaryBtnText)"/>
        <SolidColorBrush x:Key="Brush.SecondaryBtnBg" Color="$($t.SecondaryBtnBg)"/>
        <SolidColorBrush x:Key="Brush.SecondaryBtnHover" Color="$($t.SecondaryBtnHover)"/>
        <SolidColorBrush x:Key="Brush.SecondaryBtnPressed" Color="$($t.SecondaryBtnPressed)"/>
        <SolidColorBrush x:Key="Brush.SecondaryBtnBorder" Color="$($t.SecondaryBtnBorder)"/>
        <SolidColorBrush x:Key="Brush.SecondaryBtnText" Color="$($t.SecondaryBtnText)"/>
        <SolidColorBrush x:Key="Brush.CheckBoxBg" Color="$($t.CheckBoxBg)"/>
        <SolidColorBrush x:Key="Brush.CheckBoxBorder" Color="$($t.CheckBoxBorder)"/>

        <!-- Modern Primary Button Style -->
        <Style x:Key="ModernPrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource Brush.PrimaryBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource Brush.PrimaryBtnText}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="18,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="btnBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                BorderThickness="0"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="{DynamicResource Brush.PrimaryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Background" Value="{DynamicResource Brush.PrimaryBtnPressed}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Secondary Button Style -->
        <Style x:Key="ModernSecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource Brush.SecondaryBtnBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource Brush.SecondaryBtnText}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource Brush.SecondaryBtnBorder}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="16,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="secBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="secBorder" Property="Background" Value="{DynamicResource Brush.SecondaryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="secBorder" Property="Background" Value="{DynamicResource Brush.SecondaryBtnPressed}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="secBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="checkBorder"
                                Width="18"
                                Height="18"
                                CornerRadius="4"
                                Background="{DynamicResource Brush.CheckBoxBg}"
                                BorderBrush="{DynamicResource Brush.CheckBoxBorder}"
                                BorderThickness="1.5">
                            <Path x:Name="checkMark"
                                  Data="M 3,9 L 7,13 L 15,4"
                                  Stroke="{DynamicResource Brush.PrimaryBtnBg}"
                                  StrokeThickness="2"
                                  StrokeStartLineCap="Round"
                                  StrokeEndLineCap="Round"
                                  Visibility="Collapsed"
                                  HorizontalAlignment="Center"
                                  VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{DynamicResource Brush.PrimaryBtnBg}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{DynamicResource Brush.PrimaryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="checkBorder" Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern GridView Header Style -->
        <Style TargetType="GridViewColumnHeader">
            <Setter Property="Background" Value="{DynamicResource Brush.ListHeaderBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource Brush.ListHeaderText}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource Brush.ListHeaderBorder}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GridViewColumnHeader">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center"
                                              HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern ListViewItem Style -->
        <Style TargetType="ListViewItem">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Foreground" Value="{DynamicResource Brush.TextPrimary}"/>
            <Setter Property="Background" Value="{Binding RowBackground}"/>
            <Setter Property="BorderBrush" Value="{Binding RowBorder}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="Padding" Value="0,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListViewItem">
                        <Border x:Name="itemBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <GridViewRowPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="{DynamicResource Brush.ListItemHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Modern Filter CheckBox Style with Label -->
        <Style x:Key="FilterCheckBox" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Foreground" Value="{DynamicResource Brush.TextSecondary}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Border x:Name="checkBorder"
                                    Width="16"
                                    Height="16"
                                    CornerRadius="4"
                                    Background="{DynamicResource Brush.CheckBoxBg}"
                                    BorderBrush="{DynamicResource Brush.CheckBoxBorder}"
                                    BorderThickness="1.5"
                                    Margin="0,0,6,0">
                                <Path x:Name="checkMark"
                                      Data="M 2.5,7.5 L 6,11 L 13,3.5"
                                      Stroke="{DynamicResource Brush.PrimaryBtnBg}"
                                      StrokeThickness="2"
                                      StrokeStartLineCap="Round"
                                      StrokeEndLineCap="Round"
                                      Visibility="Collapsed"
                                      HorizontalAlignment="Center"
                                      VerticalAlignment="Center"/>
                            </Border>
                            <ContentPresenter VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="checkMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{DynamicResource Brush.PrimaryBtnBg}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="checkBorder" Property="BorderBrush" Value="{DynamicResource Brush.PrimaryBtnHover}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="checkBorder" Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="22,18,22,20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Top Header Card -->
        <Border Grid.Row="0"
                Background="{DynamicResource Brush.HeaderCardBg}"
                BorderBrush="{DynamicResource Brush.CardBorder}"
                BorderThickness="1"
                CornerRadius="10"
                Padding="16,14"
                Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Icon Container Badge -->
                <Border Grid.Column="0"
                        Width="44"
                        Height="44"
                        CornerRadius="9"
                        Background="{DynamicResource Brush.IconContainerBg}"
                        BorderBrush="{DynamicResource Brush.IconContainerBorder}"
                        BorderThickness="1"
                        Margin="0,0,14,0"
                        VerticalAlignment="Center">
                    <Grid HorizontalAlignment="Center" VerticalAlignment="Center">
                        <Image Name="HeaderIcon"
                               Width="28"
                               Height="28"
                               RenderOptions.BitmapScalingMode="HighQuality"/>
                        <Path Name="FallbackIcon"
                               Width="22"
                               Height="22"
                               Stretch="Uniform"
                               Fill="{DynamicResource Brush.PrimaryBtnBg}"
                               Data="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"
                               Visibility="Collapsed"/>
                    </Grid>
                </Border>

                <!-- Text Stack -->
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Name="HeaderText"
                               FontSize="16"
                               FontWeight="SemiBold"
                               Foreground="{DynamicResource Brush.TextPrimary}"
                               Margin="0,0,0,3"
                               TextWrapping="Wrap"/>
                    <TextBlock Name="InstructionText"
                               FontSize="12"
                               Foreground="{DynamicResource Brush.TextSecondary}"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Filter and Status Bar -->
        <Grid Grid.Row="1" Margin="2,0,2,8" Name="FilterBar">
            <TextBlock Name="ListSummaryText"
                       FontSize="11"
                       Foreground="{DynamicResource Brush.TextMuted}"
                       VerticalAlignment="Center"/>
            <CheckBox Name="ShowBlockedCheckBox"
                      Style="{DynamicResource FilterCheckBox}"
                      HorizontalAlignment="Right"
                      VerticalAlignment="Center"/>
        </Grid>

        <!-- App List Card -->
        <Border Grid.Row="2"
                Background="{DynamicResource Brush.ListBg}"
                BorderBrush="{DynamicResource Brush.ListBorder}"
                BorderThickness="1"
                CornerRadius="8"
                Margin="0,0,0,14"
                ClipToBounds="True">
            <ListView Name="AppList"
                      MaxHeight="280"
                      BorderThickness="0"
                      Background="Transparent"
                      ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                <ListView.View>
                    <GridView>
                        <!-- Checkbox -->
                        <GridViewColumn Width="36">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay}">
                                        <CheckBox.Style>
                                             <Style TargetType="CheckBox" BasedOn="{StaticResource {x:Type CheckBox}}">
                                                <Style.Triggers>
                                                    <DataTrigger Binding="{Binding CanUpdate}" Value="False">
                                                        <Setter Property="IsEnabled" Value="False"/>
                                                    </DataTrigger>
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

                        <!-- Application Name -->
                        <GridViewColumn Header="Application" Width="230">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <StackPanel>
                                    <TextBlock Text="{Binding Name}"
                                               FontWeight="SemiBold"
                                               FontSize="12"
                                               Foreground="{DynamicResource Brush.TextPrimary}"
                                               VerticalAlignment="Center"
                                               TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Text="{Binding ScopeDisplay}" FontSize="10"
                                               Foreground="{DynamicResource Brush.TextSecondary}"
                                               TextWrapping="Wrap"/>
                                    </StackPanel>
                                </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>

                        <!-- Available Version -->
                        <GridViewColumn Header="Available Version" Width="105">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <TextBlock Text="{Binding AvailableVersion}"
                                               FontSize="12"
                                               Foreground="{DynamicResource Brush.TextSecondary}"
                                               VerticalAlignment="Center"/>
                                 </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>

                        <!-- Required By -->
                        <GridViewColumn Header="Required By" Width="155">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <TextBlock Text="{Binding DeadlineDisplay}"
                                               ToolTip="{Binding DeadlineDisplay}"
                                               FontSize="12"
                                               Foreground="{DynamicResource Brush.TextSecondary}"
                                               VerticalAlignment="Center"/>
                                </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>

                        <!-- Time Remaining Pill Badge -->
                        <GridViewColumn Header="Time Remaining" Width="118">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <Border Background="{Binding BadgeBackground}"
                                            BorderBrush="{Binding BadgeBorder}"
                                            BorderThickness="1"
                                            CornerRadius="10"
                                            Padding="8,3"
                                            ToolTip="{Binding BlockTooltip}"
                                            HorizontalAlignment="Left"
                                            VerticalAlignment="Center">
                                        <TextBlock Text="{Binding DaysRemainingDisplay}"
                                                   FontSize="11"
                                                   FontWeight="SemiBold"
                                                   Foreground="{Binding BadgeForeground}"/>
                                    </Border>
                                </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>
                    </GridView>
                </ListView.View>
            </ListView>
        </Border>

        <!-- Footer Area -->
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Info Note -->
            <StackPanel Grid.Column="0"
                        Orientation="Horizontal"
                        VerticalAlignment="Center"
                        Margin="0,0,16,0">
                <Path Width="14"
                      Height="14"
                      Margin="0,0,7,0"
                      VerticalAlignment="Center"
                      Stretch="Uniform"
                      Fill="{DynamicResource Brush.TextMuted}"
                      Data="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>
                <TextBlock Text="Updates install in the background and restart apps if needed."
                           FontSize="11"
                           Foreground="{DynamicResource Brush.TextMuted}"
                           TextWrapping="Wrap"
                           VerticalAlignment="Center"/>
            </StackPanel>

            <!-- Action Buttons -->
            <StackPanel Grid.Column="1"
                        Orientation="Horizontal"
                        HorizontalAlignment="Right">
                <Button Name="RemindButton"
                        Style="{DynamicResource ModernSecondaryButton}"
                        Margin="0,0,10,0"/>
                <Button Name="UpdateNowButton"
                        Content="Update Now"
                        Style="{DynamicResource ModernPrimaryButton}"
                        IsDefault="True"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@
#endregion XAML

#region WINDOW SETUP
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Hook DWM immersive dark mode for title bar
$window.Add_SourceInitialized({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        if ($helper.Handle -ne [IntPtr]::Zero) {
            [NativeThemeHelper]::SetDarkMode($helper.Handle, $isDarkMode)
        }
    } catch {}
})

$appListCtrl      = $window.FindName('AppList')
$remindBtn        = $window.FindName('RemindButton')
$updateNowBtn     = $window.FindName('UpdateNowButton')
$headerTxt        = $window.FindName('HeaderText')
$instructionTxt   = $window.FindName('InstructionText')
$headerIconCtrl   = $window.FindName('HeaderIcon')
$fallbackIconCtrl = $window.FindName('FallbackIcon')
$filterBarCtrl    = $window.FindName('FilterBar')
$listSummaryTxt   = $window.FindName('ListSummaryText')
$showBlockedCb    = $window.FindName('ShowBlockedCheckBox')

# Set header text with company name if configured
if ($companyName) {
    $headerTxt.Text = "$companyName requires the following updates to be installed."
}
else {
    $headerTxt.Text = "Your organization requires the following updates to be installed."
}

# Set instruction text and button visibility based on final-day apps
$hourLabel = if ($reminderHours -ne 1) { 'hours' } else { 'hour' }
if ($script:AllFinalDay) {
    $instructionTxt.Text = "The following apps have reached their update deadline and must be updated now."
    $remindBtn.Visibility = [System.Windows.Visibility]::Collapsed
}
elseif ($script:HasFinalDayApps) {
    $instructionTxt.Text = "Apps highlighted in red have reached their deadline and must be updated now. You may select additional apps to include in this update."
    $remindBtn.Visibility = [System.Windows.Visibility]::Collapsed
}
else {
    $instructionTxt.Text = "Check the box next to apps you're ready to update now, or update all at once. If you don't update all apps now, you will be reminded in $reminderHours $hourLabel."
}

if ($pendingData.Config.InventoryComplete -eq $false) {
    $instructionTxt.Text = 'Benutzerabfrage fehlgeschlagen oder Zeitlimit erreicht. Die Liste ist unvollstaendig; bitte WAU erneut starten.'
}
# Set window and header icon from WAU's notify_icon.png if available
$iconPath = Join-Path $PSScriptRoot 'icons\notify_icon.png'
if (Test-Path $iconPath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $bitmap.EndInit()
        $window.Icon = $bitmap
        if ($headerIconCtrl) {
            $headerIconCtrl.Source = $bitmap
            $headerIconCtrl.Visibility = [System.Windows.Visibility]::Visible
        }
        if ($fallbackIconCtrl) {
            $fallbackIconCtrl.Visibility = [System.Windows.Visibility]::Collapsed
        }
    } catch {
        if ($fallbackIconCtrl) { $fallbackIconCtrl.Visibility = [System.Windows.Visibility]::Visible }
    }
}
else {
    if ($fallbackIconCtrl) {
        $fallbackIconCtrl.Visibility = [System.Windows.Visibility]::Visible
    }
}

# Set button label with configured interval
$remindBtn.Content = "Remind Me in $reminderHours $hourLabel"

# Setup Filter and Populate the ListView
$blockedCount   = @($sortedRows | Where-Object { -not $_.CanUpdate }).Count
$updatableCount = @($sortedRows | Where-Object { $_.CanUpdate }).Count

if ($blockedCount -eq 0) {
    if ($showBlockedCb) { $showBlockedCb.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($listSummaryTxt) { $listSummaryTxt.Text = "$updatableCount update$(if ($updatableCount -ne 1) { 's' }) ready" }
    $appListCtrl.ItemsSource = $sortedRows
}
elseif ($updatableCount -eq 0) {
    if ($showBlockedCb) {
        $showBlockedCb.Content = "Show blocked ($blockedCount)"
        $showBlockedCb.IsChecked = $true
    }
    if ($listSummaryTxt) { $listSummaryTxt.Text = "$blockedCount update$(if ($blockedCount -ne 1) { 's' }) blocked / deferred" }
    $appListCtrl.ItemsSource = $sortedRows
}
else {
    if ($showBlockedCb) {
        $showBlockedCb.Content = "Show blocked ($blockedCount)"
        $showBlockedCb.IsChecked = $false
    }
    if ($listSummaryTxt) { $listSummaryTxt.Text = "$updatableCount update$(if ($updatableCount -ne 1) { 's' }) ready ($blockedCount blocked hidden)" }
    $appListCtrl.ItemsSource = @($sortedRows | Where-Object CanUpdate)
}
#region INTERACTION LOGIC
# Tracks the user's chosen action. Defaults to Remind for safety.
$script:Action     = 'Remind'
$script:AllowClose = $false

$script:ApplyFilter = {
    $showBlocked = if ($showBlockedCb) { $showBlockedCb.IsChecked -eq $true } else { $true }
    if ($showBlocked) {
        $appListCtrl.ItemsSource = $sortedRows
        if ($listSummaryTxt -and $blockedCount -gt 0 -and $updatableCount -gt 0) {
            $listSummaryTxt.Text = "$updatableCount ready, $blockedCount blocked"
        }
    }
    else {
        $appListCtrl.ItemsSource = @($sortedRows | Where-Object CanUpdate)
        if ($listSummaryTxt -and $blockedCount -gt 0 -and $updatableCount -gt 0) {
            $listSummaryTxt.Text = "$updatableCount update$(if ($updatableCount -ne 1) { 's' }) ready ($blockedCount blocked hidden)"
        }
    }
    & $script:UpdateButtonState
}

if ($showBlockedCb) {
    $showBlockedCb.Add_Checked({ & $script:ApplyFilter })
    $showBlockedCb.Add_Unchecked({ & $script:ApplyFilter })
}

# Block the X button -- users must choose Remind or Update.
# Button handlers set AllowClose before calling Close().
# OS-initiated session ends (logoff/shutdown/restart) flip AllowClose so
# Windows is not blocked by the dialog reporting "this app is preventing sign-out."
[Microsoft.Win32.SystemEvents]::add_SessionEnding({
    $script:AllowClose = $true
})
$window.Add_Closing({
    param($eventSender, $e)
    if (-not $script:AllowClose) {
        $e.Cancel = $true
    }
})

# Hidden auto-dismiss timer: closes the dialog shortly before the next prompt
# without writing NextPromptTime, so the next WAU run will re-prompt with fresh data.
# Uses wall-clock comparison every 5 minutes to survive sleep/wake cycles.
$dismissTime = if ($reminderHours -gt 2) {
    [DateTime]::Now.AddHours($reminderHours).AddHours(-1)
} else {
    [DateTime]::Now.AddMinutes([math]::Max(15, ($reminderHours * 60) - 15))
}

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
    $selectedCount = @($sortedRows | Where-Object { $_.IsSelected -and $_.CanUpdate }).Count
    $updatableCount = @($sortedRows | Where-Object CanUpdate).Count
    $updateNowBtn.IsEnabled = $updatableCount -gt 0
    if ($selectedCount -eq 0) {
        $updateNowBtn.Content = 'Update Now'
        $remindBtn.IsEnabled = $true
    }
    elseif ($selectedCount -eq $updatableCount) {
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

function Set-WAUSnoozeTrigger {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Hours
    )

    $nextPrompt = (Get-Date).AddHours($Hours)
    $nextPromptTimeStr = $nextPrompt.ToString('o')

    # 1. Write NextPromptTime to HKLM registry
    try {
        Set-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -Value $nextPromptTimeStr
    }
    catch { }

    # 2. Schedule a one-time trigger on the main Winget-AutoUpdate task
    # This guarantees WAU wakes up and re-prompts the user even if WAU is only
    # scheduled to run at logon or on a daily/weekly interval.
    try {
        $wauTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if ($wauTask) {
            $snoozeTrigger = New-ScheduledTaskTrigger -Once -At $nextPrompt
            # Retain existing recurring triggers (Logon, Daily, Weekly) and discard expired Once triggers
            $cleanTriggers = @($wauTask.Triggers | Where-Object {
                if ($_.CimClass.CimClassName -ne 'MSFT_TaskTimeTrigger') { return $true }
                $parsedDt = [DateTime]::MinValue
                $_.StartBoundary -and [DateTime]::TryParse($_.StartBoundary, [ref]$parsedDt) -and $parsedDt -gt (Get-Date)
            })
            $cleanTriggers += $snoozeTrigger
            Set-ScheduledTask -TaskPath $wauTask.TaskPath -TaskName $wauTask.TaskName -Trigger $cleanTriggers | Out-Null
        }
    }
    catch { }
}

function Clear-WAUSnoozeTrigger {
    # 1. Remove NextPromptTime from HKLM registry
    Remove-ItemProperty -Path $WAURegPath -Name 'NextPromptTime' -ErrorAction SilentlyContinue

    # 2. Remove pending/expired Once triggers on Winget-AutoUpdate
    try {
        $wauTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if ($wauTask) {
            $cleanTriggers = @($wauTask.Triggers | Where-Object {
                $_.CimClass.CimClassName -ne 'MSFT_TaskTimeTrigger'
            })
            if ($cleanTriggers.Count -ne $wauTask.Triggers.Count) {
                if ($cleanTriggers.Count -gt 0) {
                    Set-ScheduledTask -TaskPath $wauTask.TaskPath -TaskName $wauTask.TaskName -Trigger $cleanTriggers | Out-Null
                }
                else {
                    # No recurring triggers remain -- set a harmless past-date trigger to avoid validation error
                    $pastTrigger = New-ScheduledTaskTrigger -Once -At "01/01/1970"
                    Set-ScheduledTask -TaskPath $wauTask.TaskPath -TaskName $wauTask.TaskName -Trigger $pastTrigger | Out-Null
                }
            }
        }
    }
    catch { }
}

if ($script:Action -eq 'UpdateNow') {
    $selectedRows = @($sortedRows | Where-Object { $_.IsSelected -and $_.CanUpdate })
    if ($selectedRows.Count -eq 0) { $selectedRows = @($sortedRows | Where-Object CanUpdate) }
    $keys = @($selectedRows | ForEach-Object Key)
    $chosen = @($pendingData.Apps | Where-Object { $_.Key -in $keys -and $_.CanUpdate })
    $selectedUserApps = @($chosen | Where-Object Scope -eq 'user')
    if ($selectedUserApps.Count -gt 0) {
        try {
            $Script:WingetSourceCustom = [string]$selectedUserApps[0].Source
            if (-not $Script:WingetSourceCustom) { $Script:WingetSourceCustom = 'winget' }
            $scopePlan = @(Invoke-WauUserOperation -Operation Plan -UserSid $pendingData.Config.UserSid -Apps $selectedUserApps -TimeoutSeconds 180)
            foreach ($app in $selectedUserApps) {
                $result = $scopePlan | Where-Object {
                    $_.Key -eq $app.Key -and $_.Id -eq $app.Id -and $_.AvailableVersion -eq $app.AvailableVersion
                } | Select-Object -First 1
                if ($result -and $result.UserInstallerSupport -in @('Supported','Unavailable','Unknown') -and
                    $result.MachineInstallerSupport -in @('Supported','Unavailable','Unknown')) {
                    $app | Add-Member NoteProperty UserInstallerSupport ([string]$result.UserInstallerSupport) -Force
                    $app | Add-Member NoteProperty MachineInstallerSupport ([string]$result.MachineInstallerSupport) -Force
                    $null = Set-WauScopePlan -App $app -Source $app.Source
                }
            }
        }
        catch {
            # Preserve the installed user scope when the applicability check is
            # inconclusive. Update-App will still require --scope user.
            [System.Windows.MessageBox]::Show("Scope check could not be completed. User updates will remain in user context.`n`n$($_.Exception.Message)", 'WAU') | Out-Null
        }
    }
    $approved = @(Select-WauApprovedUpdates -Apps $chosen -ConfirmMigration {
        param($app)
        $cleanAppName = Get-WauCleanAppName $app.Name $app.Version
        if (Show-WauScopeMigrationPrompt -App $app -DisplayName $cleanAppName) {
            $app.Name = $cleanAppName
            return $true
        }
        return $false
    })
    if ($approved.Count -gt 0) {
        # Keep selection separate from inventory: a subsequent scan cannot replace
        # the version-specific consent while UpdateNow is queued.
        $requestPath = Join-Path $PSScriptRoot 'config\update-request.json'
        $runningTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UpdateNow' -TaskPath '\WAU\' -ErrorAction SilentlyContinue
        if ((Test-Path $requestPath) -or ($runningTask -and $runningTask.State -eq 'Running')) {
            [System.Windows.MessageBox]::Show('An update request is already pending processing. Please try again later.', 'WAU') | Out-Null
        }
        else {
            Write-WauAtomicJson $requestPath ([pscustomobject]@{
                RequestId=[guid]::NewGuid().ToString('N'); CreatedUtc=[datetime]::UtcNow.ToString('o')
                UserSid=$pendingData.Config.UserSid; Apps=$approved
            })
            $updateTask = Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UpdateNow' -TaskPath '\WAU\' -ErrorAction SilentlyContinue
            if ($updateTask) {
                try { $updateTask | Start-ScheduledTask -ErrorAction Stop }
                catch {
                    Remove-Item -LiteralPath $requestPath -ErrorAction SilentlyContinue
                    [System.Windows.MessageBox]::Show("Update request could not be started: $_", 'WAU') | Out-Null
                }
            }
            else {
                # File-only deployments do not register UpdateNow. The prompt
                # already has the SYSTEM token in the interactive session.
                try {
                    $updateCommand = "& '$([System.IO.Path]::Combine($PSScriptRoot, 'WAU-UpdateNow.ps1'))'"
                    $encodedUpdate = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($updateCommand))
                    Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
                        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encodedUpdate" `
                        -WorkingDirectory $PSScriptRoot -ErrorAction Stop
                }
                catch {
                    Remove-Item -LiteralPath $requestPath -ErrorAction SilentlyContinue
                    [System.Windows.MessageBox]::Show("Updateauftrag konnte nicht gestartet werden: $_", 'WAU') | Out-Null
                }
            }
        }
    }
    if ($approved.Count -lt $pendingData.Apps.Count) { Set-WAUSnoozeTrigger -Hours $reminderHours }
    else { Clear-WAUSnoozeTrigger }
}
elseif ($script:Action -eq 'Remind') {
    # Snooze -- record NextPromptTime in registry AND set a one-time trigger on Winget-AutoUpdate
    Set-WAUSnoozeTrigger -Hours $reminderHours
}
# SilentDismiss: no action taken, no NextPromptTime written.
# Next WAU run will re-prompt with fresh data.
#endregion ACT ON CHOICE


