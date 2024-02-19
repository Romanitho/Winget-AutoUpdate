<#
.SYNOPSIS
Install and configure Winget-AutoUpdate

.DESCRIPTION
This script will:
 - Install Winget if not present
 - Install Winget-AutoUpdate to get apps daily updated
 - Install apps with Winget from a custom list file (apps.txt) or directly from popped up default list.
#>

<# UNBLOCK FILES #>

Get-ChildItem -R | Unblock-File


<# APP INFO #>

# import Appx module if the powershell version is 7/core
if ( $psversionTable.PSEdition -eq "core" ) {
    import-Module -name Appx -UseWIndowsPowershell -WarningAction:SilentlyContinue
}

$Script:WAUConfiguratorVersion = Get-Content "$PSScriptRoot\Winget-AutoUpdate\Version.txt"


<# FUNCTIONS #>

. "$PSScriptRoot\Winget-AutoUpdate\functions\Update-WinGet.ps1"
. "$PSScriptRoot\Winget-AutoUpdate\functions\Get-WingetCmd.ps1"

#Function to start or update popup
Function Start-PopUp ($Message) {

    if (!$PopUpWindow) {

        #Create window
        $inputXML = @"
<Window x:Class="WAUConfigurator_v3.PopUp"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:WAUConfigurator_v3"
        mc:Ignorable="d"
        Title="WAU Configurator {0}" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Width="280" MinHeight="130" SizeToContent="Height">
    <Grid>
        <TextBlock x:Name="PopUpLabel" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" Margin="20" TextAlignment="Center"/>
    </Grid>
</Window>
"@

        [xml]$XAML = ($inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window') -f $WAUConfiguratorVersion

        #Read the form
        $Reader = (New-Object System.Xml.XmlNodeReader $XAML)
        $Script:PopUpWindow = [Windows.Markup.XamlReader]::Load($Reader)
        $PopUpWindow.Icon = $IconBase64

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

#Function to close popup
Function Close-PopUp {
    $Script:PopUpWindow.Close()
    $Script:PopUpWindow = $null
}

function Get-WingetAppInfo ($SearchApp) {
    class Software {
        [string]$Name
        [string]$Id
    }

    #Search for winget apps
    $AppResult = & $Winget search $SearchApp --accept-source-agreements --source winget | Out-String

    #Start Convertion of winget format to an array. Check if "-----" exists
    if (!($AppResult -match "-----")) {
        Start-PopUp "No application found!"
        Start-Sleep 2
        Close-PopUp
        return
    }

    #Split winget output to lines
    $lines = $AppResult.Split([Environment]::NewLine) | Where-Object { $_ }

    # Find the line that starts with "------"
    $fl = 0
    while (-not $lines[$fl].StartsWith("-----")) {
        $fl++
    }

    $fl = $fl - 1

    #Get header titles [without remove seperator]
    $index = $lines[$fl] -split '(?<=\s)(?!\s)'

    # Line $fl has the header, we can find char where we find ID and Version [and manage non latin characters]
    $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
    $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length

    # Now cycle in real package and split accordingly
    $searchList = @()
    For ($i = $fl + 2; $i -le $lines.Length; $i++) {
        $line = $lines[$i] -replace "[\u2026]", " " #Fix "..." in long names
        # If line contains an ID (Alphanumeric | Literal "." | Alphanumeric)
        if ($line -match "\w\.\w") {
            $software = [Software]::new()
            #Manage non latin characters
            $nameDeclination = $($line.Substring(0, $idStart) -replace '[\u4e00-\u9fa5]', '**').Length - $line.Substring(0, $idStart).Length
            $software.Name = $line.Substring(0, $idStart - $nameDeclination).TrimEnd()
            $software.Id = $line.Substring($idStart - $nameDeclination, $versionStart - $idStart).TrimEnd()
            #add formated soft to list
            $searchList += $software
        }
    }
    return $searchList
}

function Get-WingetInstalledApps {

    #Json File where to export install apps
    $jsonFile = "$env:TEMP\Installed_Apps.json"

    #Get list of installed Winget apps to json file
    & $Winget export -o $jsonFile --accept-source-agreements | Out-Null

    #Convert from json file
    $InstalledApps = get-content $jsonFile | ConvertFrom-Json

    #Return app list
    return $InstalledApps.Sources.Packages.PackageIdentifier | Sort-Object | Get-Unique
}

function Start-Installations {

    ## WAU PART ##

    #Download and install Winget-AutoUpdate if box is checked
    if ($InstallWAU) {

        Start-PopUp "Installing WAU..."

        #Configure parameters
        $WAUParameters = "-Silent "
        if ($WAUDoNotUpdate) {
            $WAUParameters += "-DoNotUpdate "
        }
        if ($WAUDisableAU) {
            $WAUParameters += "-DisableWAUAutoUpdate "
        }
        if ($WAUNotificationLevel) {
            $WAUParameters += "-NotificationLevel $WAUNotificationLevel "
        }
        if ($WAUFreqUpd) {
            $WAUParameters += "-UpdatesInterval $WAUFreqUpd "
        }
        if ($WAUAtUserLogon) {
            $WAUParameters += "-UpdatesAtLogon "
        }
        if ($WAUonMetered) {
            $WAUParameters += "-RunOnMetered "
        }
        if ($WAUUseWhiteList) {
            $WAUParameters += "-UseWhiteList "
            if ($WAUListPath) {
                Copy-Item $WAUListPath -Destination "$PSScriptRoot\included_apps.txt" -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            if ($WAUListPath) {
                Copy-Item $WAUListPath -Destination "$PSScriptRoot\excluded_apps.txt" -Force -ErrorAction SilentlyContinue
            }
        }
        if ($WAUDesktopShortcut) {
            $WAUParameters += "-DesktopShortcut "
        }
        if ($WAUStartMenuShortcut) {
            $WAUParameters += "-StartMenuShortcut "
        }
        if ($WAUInstallUserContext) {
            $WAUParameters += "-InstallUserContext "
        }

        #Install Winget-Autoupdate
        Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command ""& '$PSScriptRoot\Winget-AutoUpdate-Install.ps1' $WAUParameters""" -Wait -Verb RunAs
    }


    ## WINGET-INSTALL PART ##

    #Run Winget-Install script if box is checked
    if ($AppToInstall) {
        Start-PopUp "Installing applications..."
        $WAUInstallPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\" -Name InstallLocation

        #Try with admin rights.
        try {
            Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$WAUInstallPath\Winget-Install.ps1 -AppIDs $AppToInstall`"" -Wait -Verb RunAs
        }
        catch {
            Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$WAUInstallPath\Winget-Install.ps1 -AppIDs $AppToInstall`"" -Wait
        }
    }


    ## ADMIN PART ##

    if ($CMTrace) {
        Start-PopUp "Installing CMTrace..."
        $CMToolkitLink = "https://github.com/Romanitho/Winget-Install-GUI/raw/main/Tools/cmtrace.exe"
        $CMToolkitPath = "C:\Tools\CMTrace.exe"
        Invoke-WebRequest $CMToolkitLink -OutFile (New-Item -Path $CMToolkitPath -Force)
        Start-Sleep 1
    }

    if ($AdvancedRun) {
        Start-PopUp "Installing AdvancedRun..."
        $AdvancedRunLink = "https://www.nirsoft.net/utils/advancedrun-x64.zip"
        $AdvancedRunPath = "C:\Tools\advancedrun-x64.zip"
        Invoke-WebRequest $AdvancedRunLink -OutFile (New-Item -Path $AdvancedRunPath -Force)
        Expand-Archive -Path $AdvancedRunPath -DestinationPath "C:\Tools\AdvancedRun" -Force
        Start-Sleep 1
        Remove-Item $AdvancedRunPath
    }

    if ($UninstallView) {
        Start-PopUp "Installing UninstallView..."
        $UninstallViewLink = "https://www.nirsoft.net/utils/uninstallview-x64.zip"
        $UninstallViewPath = "C:\Tools\uninstallview-x64.zip"
        Invoke-WebRequest $UninstallViewLink -OutFile (New-Item -Path $UninstallViewPath -Force)
        Expand-Archive -Path $UninstallViewPath -DestinationPath "C:\Tools\UninstallView" -Force
        Start-Sleep 1
        Remove-Item $UninstallViewPath
    }

    #If Popup Form is showing, close
    if ($PopUpWindow) {
        #Installs finished
        Start-PopUp "Done!"
        Start-Sleep 2
        #Close Popup
        Close-PopUp
    }

    if ($CMTrace -or $AdvancedRun -or $UninstallView) {
        Start-Process "C:\Tools"
    }
}

function Start-Uninstallations ($AppToUninstall) {
    #Download and run Winget-Install script if box is checked
    if ($AppToUninstall) {

        Start-PopUp "Uninstalling applications..."

        #Run Winget-Install -Uninstall
        $AppsToUninstall = "'$($AppToUninstall -join "','")'"
        Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$PSScriptRoot\Winget-AutoUpdate\Winget-Install.ps1 -AppIDs $AppsToUninstall -Uninstall`"" -Wait -Verb RunAs

        Close-PopUp
    }
}

function Get-WAUInstallStatus {
    $WAUVersion = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayVersion -ErrorAction SilentlyContinue
    if ($WAUVersion -eq $WAUConfiguratorVersion) {
        $WAULabelText = "WAU is currently installed (v$WAUVersion)."
        $WAUStatus = "Green"
        $WAUInstalled = $true
    }
    elseif ($WAUVersion) {
        $WAULabelText = "WAU is currently installed but in a different version - v$WAUVersion"
        $WAUStatus = "DarkOrange"
        $WAUInstalled = $true
    }
    else {
        $WAULabelText = "WAU is not installed."
        $WAUStatus = "Red"
        $WAUInstalled = $false
    }
    return $WAULabelText, $WAUStatus, $WAUInstalled
}

function Get-WAUConfiguratorLatestVersion {

    ### FORM CREATION ###

    #Get latest stable info
    $WAUConfiguratorURL = 'https://api.github.com/repos/Romanitho/Winget-AutoUpdate/releases/latest'
    $WAUConfiguratorLatestVersion = (((Invoke-WebRequest $WAUConfiguratorURL -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")).Replace("-", ".")

    if ([version]$WAUConfiguratorVersion -lt [version]$WAUConfiguratorLatestVersion) {

        #Create window
        $inputXML = @"
<Window x:Class="WAUConfigurator.Update"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:local="clr-namespace:Winget_Intune_Packager"
    mc:Ignorable="d"
    Title="WAU Configurator {0} - Update available" ResizeMode="NoResize" SizeToContent="WidthAndHeight" WindowStartupLocation="CenterScreen" Topmost="True">
    <Grid>
        <TextBlock x:Name="TextBlock" HorizontalAlignment="Center" TextWrapping="Wrap" VerticalAlignment="Center" Margin="26,26,26,60" MaxWidth="480" Text="A New WAU Configurator version is available. Version $WAUConfiguratorLatestVersion"/>
        <StackPanel Height="32" Orientation="Horizontal" UseLayoutRounding="False" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="6">
            <Button x:Name="GithubButton" Content="See on GitHub" Margin="4" Width="100"/>
            <Button x:Name="DownloadButton" Content="Download" Margin="4" Width="100"/>
            <Button x:Name="SkipButton" Content="Skip" Margin="4" Width="100" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

        [xml]$XAML = ($inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window') -f $WAUConfiguratorVersion

        #Read the form
        $Reader = (New-Object System.Xml.XmlNodeReader $xaml)
        $UpdateWindow = [Windows.Markup.XamlReader]::Load($Reader)
        $UpdateWindow.Icon = $IconBase64

        #Store Form Objects In PowerShell
        $FormObjects = $XAML.SelectNodes("//*[@Name]")
        $FormObjects | ForEach-Object {
            Set-Variable -Name "$($_.Name)" -Value $UpdateWindow.FindName($_.Name) -Scope Script
        }


        ## ACTIONS ##

        $GithubButton.add_click(
            {
                $UpdateWindow.Topmost = $false
                [System.Diagnostics.Process]::Start("https://github.com/Romanitho/Winget-AutoUpdate/releases")
            }
        )

        $DownloadButton.add_click(
            {
                $WAUConfiguratorSaveFile = New-Object System.Windows.Forms.SaveFileDialog
                $WAUConfiguratorSaveFile.Filter = "Zip file (*.zip)|*.zip"
                $WAUConfiguratorSaveFile.FileName = "WAU-Configurator_$WAUConfiguratorLatestVersion.zip"
                $response = $WAUConfiguratorSaveFile.ShowDialog() # $response can return OK or Cancel
                if ( $response -eq 'OK' ) {
                    Start-PopUp "Downloading WAU Configurator $WAUConfiguratorLatestVersion..."
                    $WAUConfiguratorDlLink = "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v$WAUConfiguratorLatestVersion/WAU-Configurator.zip"
                    Invoke-WebRequest -Uri $WAUConfiguratorDlLink -OutFile $WAUConfiguratorSaveFile.FileName -UseBasicParsing
                    $UpdateWindow.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    $UpdateWindow.Close()
                    Start-Sleep 3

                    #Open folder
                    Start-Process (Split-Path -parent $WAUConfiguratorSaveFile.FileName)

                    Close-PopUp
                    Exit 0
                }
            }
        )

        $SkipButton.add_click(
            {
                $UpdateWindow.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $UpdateWindow.Close()
            }
        )


        ## RETURNS ##
        #Show Wait form
        $UpdateWindow.ShowDialog() | Out-Null
    }
}

function Start-InstallGUI {

    ### FORM CREATION ###

    # GUI XAML file
    $inputXML = @"
<Window x:Name="WAUConfiguratorForm" x:Class="WAUConfigurator_v3.MainWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:local="clr-namespace:WAUConfigurator_v3"
    mc:Ignorable="d"
    Title="WAU Configurator {0}" Height="700" Width="540" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen">
<Grid>
    <Grid.Background>
        <SolidColorBrush Color="#FFF0F0F0"/>
    </Grid.Background>
    <TabControl x:Name="WAUConfiguratorTabControl" Margin="10,10,10,44">
        <TabItem x:Name="WAUTabPage" Header="Configure WAU">
            <Grid>
                <CheckBox x:Name="WAUCheckBox" Content="Install WAU (Winget-AutoUpdate) - v{0}" Margin="10,20,0,0" VerticalAlignment="Top" HorizontalAlignment="Left" ToolTip="Install WAU with system and user context executions. Applications installed in system context will be ignored under user context."/>
                <GroupBox x:Name="WAUConfGroupBox" Header="Configurations" VerticalAlignment="Top" Margin="10,46,10,0" Height="134" IsEnabled="False">
                    <Grid>
                        <CheckBox x:Name="WAUDoNotUpdateCheckBox" Content="Do not run WAU just after install" Margin="10,10,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" ToolTip="Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation."/>
                        <CheckBox x:Name="WAUDisableAUCheckBox" Content="Disable WAU Self-Update" Margin="10,34,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" ToolTip="Disable WAU update checking. By default, WAU auto updates if new version is available on Github."/>
                        <CheckBox x:Name="WAUonMeteredCheckBox" Content="Run WAU on metered connexion" Margin="10,58,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" ToolTip="Force WAU to run on metered connections. Not recommanded on connection sharing for instance as it might consume cellular data."/>
                        <TextBlock x:Name="NotifLevelLabel" HorizontalAlignment="Left" Margin="10,85,0,0" TextWrapping="Wrap" Text="Notification level" VerticalAlignment="Top" ToolTip="Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup)."/>
                        <ComboBox x:Name="NotifLevelComboBox" HorizontalAlignment="Left" Margin="120,82,0,0" VerticalAlignment="Top" Width="110" ToolTip="Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).">
                            <ComboBoxItem Content="Full" IsSelected="True"/>
                            <ComboBoxItem Content="SuccessOnly"/>
                            <ComboBoxItem Content="None"/>
                        </ComboBox>
                        <CheckBox x:Name="WAUInstallUserContextCheckBox" Margin="250,10,0,0" HorizontalAlignment="Left" VerticalAlignment="Top" Content="Run WAU in user context too" ToolTip="Install WAU with system and user context executions (by default, only system for admin rights purpose). Applications installed in system context will be ignored under user context." IsChecked="True"/>
                    </Grid>
                </GroupBox>
                <GroupBox x:Name="WAUFreqGroupBox" Header="Update Frequency" VerticalAlignment="Top" Margin="10,185,10,0" Height="84" IsEnabled="False">
                    <Grid>
                        <StackPanel x:Name="WAUFreqLayoutPanel" VerticalAlignment="Top" Orientation="Horizontal">
                            <RadioButton Content="Daily" Margin="10"/>
                            <RadioButton Content="Weekly" Margin="10"/>
                            <RadioButton Content="Biweekly" Margin="10"/>
                            <RadioButton Content="Monthly" Margin="10"/>
                            <RadioButton Content="Never" Margin="10" IsChecked="True"/>
                        </StackPanel>
                        <CheckBox x:Name="UpdAtLogonCheckBox" Content="Run WAU at user logon" Margin="10,40,0,0" IsChecked="True"/>
                    </Grid>
                </GroupBox>
                <GroupBox x:Name="WAUWhiteBlackGroupBox" Header="White / Black List" VerticalAlignment="Top" Margin="10,274,10,0" Height="88" IsEnabled="False">
                    <Grid>
                        <StackPanel x:Name="WAUListLayoutPanel" VerticalAlignment="Top" Orientation="Horizontal">
                            <RadioButton x:Name="DefaultRadioBut" Content="Default" Margin="10" IsChecked="True"/>
                            <RadioButton x:Name="BlackRadioBut" Content="BlackList" Margin="10" ToolTip="Exclude apps from update job (for instance, apps to keep at a specific version or apps with built-in auto-update)"/>
                            <RadioButton x:Name="WhiteRadioBut" Content="WhiteList" Margin="10" ToolTip="Update only selected apps"/>
                        </StackPanel>
                        <TextBox x:Name="WAUListFileTextBox" VerticalAlignment="Top" Margin="10,36,106,0" Height="24" VerticalContentAlignment="Center" IsEnabled="False"/>
                        <Button x:Name="WAULoadListButton" Content="Load list" Width="90" Height="24" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,36,10,0" IsEnabled="False"/>
                    </Grid>
                </GroupBox>
                <GroupBox x:Name="WAUShortcutsGroupBox" Header="Shortcuts" VerticalAlignment="Top" Margin="10,367,10,0" Height="80" IsEnabled="False">
                    <Grid>
                        <CheckBox x:Name="DesktopCheckBox" Content="Desktop" Margin="10,10,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                        <CheckBox x:Name="StartMenuCheckBox" Content="Start Menu" Margin="10,34,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                    </Grid>
                </GroupBox>
                <TextBlock x:Name="WAUStatusLabel" HorizontalAlignment="Right" VerticalAlignment="Bottom" Text="WAU installed status" TextAlignment="Right" Margin="0,0,105,14"/>
                <Button x:Name="UninstallWAUButton" Content="Uninstall WAU" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="90" Height="24" Margin="0,0,10,10" IsEnabled="False"/>
            </Grid>
        </TabItem>
        <TabItem x:Name="AppsTabPage" Header="Install Winget Apps" IsEnabled="False">
            <Grid>
                <Label x:Name="SearchLabel" Content="Search for an app:" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="10,10,0,0"/>
                <TextBox x:Name="SearchTextBox" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="10,36,0,0" Width="380" Height="24" VerticalContentAlignment="Center"/>
                <Button x:Name="SearchButton" Content="Search" HorizontalAlignment="Right" VerticalAlignment="Top" Width="90" Height="24" Margin="0,36,10,0" IsDefault="True"/>
                <Label x:Name="SubmitLabel" Content="Select the matching Winget AppID:" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="10,70,0,0"/>
                <Button x:Name="SubmitButton" Content="Add to list" HorizontalAlignment="Right" VerticalAlignment="Top" Width="90" Height="24" Margin="0,96,10,0"/>
                <Label x:Name="AppListLabel" Content="Current Application list:" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="10,130,0,0"/>
                <Button x:Name="SaveListButton" Content="Save list to file" HorizontalAlignment="Right" VerticalAlignment="Top" Width="90" Height="24" Margin="0,156,10,0"/>
                <Button x:Name="OpenListButton" Content="Import from file" HorizontalAlignment="Right" VerticalAlignment="Top" Width="90" Height="24" Margin="0,185,10,0"/>
                <Button x:Name="RemoveButton" Content="Remove" HorizontalAlignment="Right" VerticalAlignment="Top" Width="90" Height="24" Margin="0,214,10,0"/>
                <Button x:Name="UninstallButton" Content="Uninstall" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="90" Height="24" Margin="0,0,10,39"/>
                <Button x:Name="InstalledAppButton" Content="List installed" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="90" Height="24" Margin="0,0,10,10"/>
                <ListBox x:Name="AppListBox" HorizontalAlignment="Left" Margin="10,156,0,10" Width="380" SelectionMode="Extended"/>
                <ComboBox x:Name="SubmitComboBox" HorizontalAlignment="Left" Margin="10,96,0,0" VerticalAlignment="Top" Width="380" Height="24" IsEditable="True"/>
            </Grid>
        </TabItem>
        <TabItem x:Name="AdminTabPage" Header="Admin Tools" Visibility="Hidden">
            <Grid>
                <CheckBox x:Name="AdvancedRunCheckBox" Content="Install NirSoft AdvancedRun" Margin="10,20,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                <CheckBox x:Name="UninstallViewCheckBox" Content="Install NirSoft UninstallView" Margin="10,44,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                <CheckBox x:Name="CMTraceCheckBox" Content="Install CMTrace" Margin="10,68,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
                <Button x:Name="LogButton" Content="Open Log Folder" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="110" Height="24" Margin="0,0,10,10"/>
            </Grid>
        </TabItem>
    </TabControl>
    <Button x:Name="CloseButton" Content="Close" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,10,10" Width="90" Height="24"/>
    <Button x:Name="InstallButton" Content="Install" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,105,10" Width="90" Height="24"/>
    <TextBlock x:Name="WAUConfiguratorLinkLabel" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10,0,0,14">
        <Hyperlink NavigateUri="https://github.com/Romanitho/Winget-AutoUpdate">More info about WAU</Hyperlink>
    </TextBlock>
</Grid>
</Window>
"@

    #Create window
    [xml]$XAML = ($inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window') -f $WAUConfiguratorVersion

    #Read the form
    $Reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $script:WAUConfiguratorForm = [Windows.Markup.XamlReader]::Load($reader)

    #Store Form Objects In PowerShell
    $FormObjects = $xaml.SelectNodes("//*[@Name]")
    $FormObjects | ForEach-Object {
        Set-Variable -Name "$($_.Name)" -Value $WAUConfiguratorForm.FindName($_.Name) -Scope Script
    }

    # Customization
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $WAUListOpenFile = New-Object System.Windows.Forms.OpenFileDialog
    $WAUListOpenFile.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $WAUInstallStatus = Get-WAUInstallStatus
    $WAUStatusLabel.Text = $WAUInstallStatus[0]
    $WAUStatusLabel.Foreground = $WAUInstallStatus[1]
    $AppsTabPage.IsEnabled = $WAUInstallStatus[2]
    $UninstallWAUButton.IsEnabled = $WAUInstallStatus[2]
    $WAUConfiguratorForm.Icon = $IconBase64



    ### FORM ACTIONS ###

    ##
    # "Configure WAU" Tab
    ##
    $WAUCheckBox.add_click(
        {
            if ($WAUCheckBox.IsChecked -eq $true) {
                $WAUConfGroupBox.IsEnabled = $true
                $WAUFreqGroupBox.IsEnabled = $true
                $WAUWhiteBlackGroupBox.IsEnabled = $true
                $WAUShortcutsGroupBox.IsEnabled = $true
            }
            elseif ($WAUCheckBox.IsChecked -eq $false) {
                $WAUConfGroupBox.IsEnabled = $false
                $WAUFreqGroupBox.IsEnabled = $false
                $WAUWhiteBlackGroupBox.IsEnabled = $false
                $WAUShortcutsGroupBox.IsEnabled = $false
            }
        }
    )

    $WAUMoreInfoLabel.Add_PreviewMouseDown(
        {
            [System.Diagnostics.Process]::Start("https://github.com/Romanitho/Winget-AutoUpdate")
        }
    )

    $BlackRadioBut.add_click(
        {
            $WAULoadListButton.IsEnabled = $true
        }
    )

    $WhiteRadioBut.add_click(
        {
            $WAULoadListButton.IsEnabled = $true
        }
    )

    $DefaultRadioBut.add_click(
        {
            $WAULoadListButton.IsEnabled = $false
            $WAUListFileTextBox.Clear()
        }
    )

    $WAULoadListButton.add_click(
        {
            $response = $WAUListOpenFile.ShowDialog() # $response can return OK or Cancel
            if ( $response -eq 'OK' ) {
                $WAUListFileTextBox.Text = $WAUListOpenFile.FileName
            }
        }
    )

    $UninstallWAUButton.add_click(
        {
            #Uninstall WAU from registry command
            $Arguments = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate" -Name "UninstallString"
            Start-Process "cmd.exe" -ArgumentList "/c $Arguments" -Wait -Verb RunAs
            $WAUInstallStatus = Get-WAUInstallStatus
            $WAUStatusLabel.Text = $WAUInstallStatus[0]
            $WAUStatusLabel.Foreground = $WAUInstallStatus[1]
            $AppsTabPage.IsEnabled = $WAUInstallStatus[2]
            $UninstallWAUButton.IsEnabled = $WAUInstallStatus[2]
            $AppListBox.Items.Clear()
        }
    )

    ##
    # "Select Apps" Tab
    ##
    $SearchButton.add_click(
        {
            if ($SearchTextBox.Text) {
                Start-PopUp "Searching..."
                $SubmitComboBox.Items.Clear()
                $List = Get-WingetAppInfo $SearchTextBox.Text
                foreach ($L in $List) {
                    $SubmitComboBox.Items.Add($L.ID)
                }
                $SubmitComboBox.SelectedIndex = 0
                Close-PopUp
            }
        }
    )

    $SubmitButton.add_click(
        {
            $AddAppToList = $SubmitComboBox.Text
            if ($AddAppToList -ne "" -and $AppListBox.Items -notcontains $AddAppToList) {
                $AppListBox.Items.Add($AddAppToList)
            }
        }
    )

    $RemoveButton.add_click(
        {
            if (!$AppListBox.SelectedItems) {
                Start-PopUp "Please select apps to remove..."
                Start-Sleep 2
                Close-PopUp
            }
            while ($AppListBox.SelectedItems) {
                $AppListBox.Items.Remove($AppListBox.SelectedItems[0])
            }
        }
    )

    $SaveListButton.add_click(
        {
            $response = $SaveFileDialog.ShowDialog() # $response can return OK or Cancel
            if ( $response -eq 'OK' ) {
                $AppListBox.Items | Out-File $SaveFileDialog.FileName -Append
                Start-PopUp "File saved to:`n$($SaveFileDialog.FileName)"
                Start-Sleep 2
                Close-PopUp
            }
        }
    )

    $OpenListButton.add_click(
        {
            $response = $OpenFileDialog.ShowDialog() # $response can return OK or Cancel
            if ( $response -eq 'OK' ) {
                $FileContent = Get-Content $OpenFileDialog.FileName
                foreach ($App in $FileContent) {
                    if ($App -ne "" -and $AppListBox.Items -notcontains $App) {
                        $AppListBox.Items.Add($App)
                    }
                }
            }
        }
    )

    $InstalledAppButton.add_click(
        {
            Start-PopUp "Getting installed apps..."
            $AppListBox.Items.Clear()
            $List = Get-WingetInstalledApps
            foreach ($L in $List) {
                $AppListBox.Items.Add($L)
            }
            Close-PopUp
        }
    )

    $UninstallButton.add_click(
        {
            if ($AppListBox.SelectedItems) {
                Start-Uninstallations $AppListBox.SelectedItems
                $WAUInstallStatus = Get-WAUInstallStatus
                $WAUStatusLabel.Text = $WAUInstallStatus[0]
                $WAUStatusLabel.Foreground = $WAUInstallStatus[1]
                $AppsTabPage.IsEnabled = $WAUInstallStatus[2]
                $UninstallWAUButton.IsEnabled = $WAUInstallStatus[2]
                $AppListBox.Items.Clear()
            }
            else {
                Start-PopUp "Please select apps to uninstall..."
                Start-Sleep 2
                Close-PopUp
            }
        }
    )

    ##
    # "Admin Tool" Tab by hitting F9 Key
    ##
    $WAUConfiguratorForm.Add_KeyDown(
        {
            if ($_.Key -eq "F9") {
                $AdminTabPage.Visibility = "Visible"
            }
        }
    )

    $LogButton.add_click(
        {
            try {
                $LogPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\" -Name InstallLocatifon
                Start-Process "$LogPath\Logs"
            }
            catch {
                Start-PopUp "Log location not found."
                Start-Sleep 2
                Close-PopUp
            }
        }
    )

    ##
    # Global Form
    ##
    $WAUConfiguratorLinkLabel.Add_PreviewMouseDown(
        {
            [System.Diagnostics.Process]::Start("https://github.com/Romanitho/Winget-AutoUpdate")
        }
    )

    $InstallButton.add_click(
        {
            if ($AppListBox.Items) {
                $Script:AppToInstall = "'$($AppListBox.Items -join "','")'"
            }
            else {
                $Script:AppToInstall = $null
            }
            $Script:InstallWAU = $WAUCheckBox.IsChecked
            $Script:WAUDoNotUpdate = $WAUDoNotUpdateCheckBox.IsChecked
            $Script:WAUDisableAU = $WAUDisableAUCheckBox.IsChecked
            $Script:WAUAtUserLogon = $UpdAtLogonCheckBox.IsChecked
            $Script:WAUNotificationLevel = $NotifLevelComboBox.Text
            $Script:WAUUseWhiteList = $WhiteRadioBut.IsChecked
            $Script:WAUListPath = $WAUListFileTextBox.Text
            $Script:WAUFreqUpd = $WAUFreqLayoutPanel.Children.Where({ $_.IsChecked -eq $true }).content
            $Script:AdvancedRun = $AdvancedRunCheckBox.IsChecked
            $Script:UninstallView = $UninstallViewCheckBox.IsChecked
            $Script:CMTrace = $CMTraceCheckBox.IsChecked
            $Script:WAUonMetered = $WAUonMeteredCheckBox.IsChecked
            $Script:WAUDesktopShortcut = $DesktopCheckBox.IsChecked
            $Script:WAUStartMenuShortcut = $StartMenuCheckBox.IsChecked
            $Script:WAUInstallUserContext = $WAUInstallUserContextCheckBox.IsChecked
            Start-Installations
            $WAUCheckBox.IsChecked = $false
            $WAUConfGroupBox.IsEnabled = $false
            $WAUFreqGroupBox.IsEnabled = $false
            $WAUShortcutsGroupBox.IsEnabled = $false
            $WAUWhiteBlackGroupBox.IsEnabled = $false
            $AdvancedRunCheckBox.IsChecked = $false
            $UninstallViewCheckBox.IsChecked = $false
            $CMTraceCheckBox.IsChecked = $false
            $WAUInstallStatus = Get-WAUInstallStatus
            $WAUStatusLabel.Text = $WAUInstallStatus[0]
            $WAUStatusLabel.Foreground = $WAUInstallStatus[1]
            $AppsTabPage.IsEnabled = $WAUInstallStatus[2]
            $UninstallWAUButton.IsEnabled = $WAUInstallStatus[2]
        }
    )

    $CloseButton.add_click(
        {
            $WAUConfiguratorForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $WAUConfiguratorForm.Close()
        }
    )

    # Shows the form
    $Script:FormReturn = $WAUConfiguratorForm.ShowDialog()
}


<# MAIN #>

#Load assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

#Set some variables
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = "SilentlyContinue"
$Script:ErrorActionPreference = "SilentlyContinue"
$Script:AppToInstall = $null
$Script:InstallWAU = $null
$IconBase64 = [Convert]::FromBase64String("AAABAAEAICAAAAEAIACoEAAAFgAAACgAAAAgAAAAQAAAAAEAIAAAAAAAABAAAMMOAADDDgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA39DIHd7Qx2Pdz8ec3c7FzNzOxezczcT/283E/9vNxOzbzcTQ3M7EoNzOxWDcz8QeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA39LLNd7RyZne0Mjq39LK/+PY0f/p4Nv/7ebh/+/p5v/v6eb/7eXh/+je2f/i1s//3dDH/9zNxO7czsSd3M/GLwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4NLNEODTzIzf0sry4tbP/+3n4v/39fP//v39//////////////////////////////////38/P/39PL/7OTg/+HUzf/czcT03M7Gid3Pxw4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAODUzSrg08zM4dXN/+3m4v/7+fj/////////////////////////////////////////////////////////////////+/r5/+vk3//e0Mj/3M7FzNzPxi0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADh1s864dTN4eXb1f/38/H///////////////////////////////////////////////////////////////////////////////////////Xx7//i1s//3M7G4d7QyDoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA49bPLeLVzuHn3df/+vn4//////////////////////////////////////////////////////////////////////////////////////////////////r49//j2NH/3M/G4d3RxyoAAAAAAAAAAAAAAAAAAAAAAAAAAOLa0Q7i18/M5tzW//v5+P/////////////////////////////////+/Pr/9+ja/+/Uv//szLz/7My7/+/Sv//25tf//vv5//////////////////////////////////r49//j19D/3c/HzN/QyRAAAAAAAAAAAAAAAAAAAAAA49nSieTa0//39PL////////////////////////////+/fv/8Na+/+Ciav/XfwD/1HAA/9JoAP/RZgD/0mwA/9V5AP/dm2L/79S////9+/////////////////////7///////bz8P/f0sv/39HJjAAAAAAAAAAAAAAAAOPa0y/k2dH07+rm////////////////////////////+/Ts/+Sxhf/WeAD/1XUA/9uPPv/krnv/6cGk/+nBpP/jrXz/2ow9/9NuAP/TbwD/462E//ry6f//////9+ng/+Wzif/47OL//////+3m4f/e0Mjy3tLLNQAAAAAAAAAA5drTnejf2f/8+/v///////////////////////vz6v/ho2P/1ncA/9yQOf/u0Lb//Pbw///+/P/////////////+/P/79e7/7c61/9qLOv/SagD/3pth//348f/rzL3/zlMA/+vKuf//////+/n4/+LWz//f0sqZAAAAAOXc1B7l29Tu8evn/////////////////////////fv/5rWG/9d5AP/gnVT/+e3h////////////////////////////////////////////+Ozh/92WUf/SbAD/5bSQ/+rItf/QYQD/68q7////////////7ufj/9/Syurg08sd5tzWYOfd1//59/b///////////////////////HXv//ZgAD/3pU9//nt4f//////////////////////////////////////////////////////+Ozh/9qKOf/WfAD/3JNL/9JtAP/ry7z////////////49fP/4dXO/+HUzGPm3dag6uLd//79/f////////////////////7/6b2P/9l7AP/w07j/////////////////////////////////////////////////////////////////79K5/9V4AP/VewD/03EA/+vLvP////////////79/f/l29X/4NTMnOfd19Dv6OT////////////////////////////68Ob/89rD//779//////////////////////////////////////////////////57eP/68ar/+rFqf/ou5f/2IMa/9Z+AP/UcwD/68u7/////////////////+vj3//g1MzM6N7Y7PLt6////////////////////////////////////////////////////////////////////////////////////////////+m+lf/TaAD/1G8A/9RwAP/WdwD/1XYA/9NsAP/tzrz/////////////////7+nl/+HVzezo39n/9PDu////////////////////////////////////////////////////////////////////////////////////////////+e7k/+3Puv/tzrz/7c28/+3NvP/szbv/7s+8//vz6//////////////////y7On/4tXO/+ng2v/18e7//////////////////PXs//HVvf/v0rz/79K8/+/SvP/v0bz/79K6//rv5f////////////////////////////////////////////////////////////////////////////////////////////Lt6v/i18//6eHb7PPv7P/////////////////x1bz/3IgA/92MAP/diwD/24UA/9uCAP/ZewD/68OX////////////////////////////////////////////////////////////////////////////////////////////8Orn/+PX0Ozq4dzM8ezo//////////////////DTvP/ekAD/35YQ/+CYJP/sxJr/7syr/+7Mrf/57uP//////////////////////////////////////////////////vv3//LZw//67+b////////////////////////////t5uH/5NjS0Ovi3Zzu5+P//v7+////////////8dS8/9+SAP/glgD/35MA//LZvP/////////////////////////////////////////////////////////////////w07j/2HkA/+m8jv////7//////////////////v39/+ng2v/l2tOg7OTfY+zk4P/7+Pf////////////x1bz/35IA/+WqU//hmQb/46JA//rv4v//////////////////////////////////////////////////////+e7i/9+ZPv/agwD/8de////////////////////////59/X/5tzW/+Xb1WDs5OAd7OTf6vXw7v////////////HVvP/fjwD/8NO2/+zDlP/fkAD/5qxZ//rw4v////////////////////////////////////////////ru4v/ipFb/2oIA/+i3h////fv///////////////////////Hs6P/m3NXu5dzVHgAAAADs5eCZ7ufj//38+///////8dW6/96KAP/x1r7//fry/+eyaP/fkAD/5KRD//LXuP/89+/////9//////////////79//z38f/x1bj/4Zw9/9uFAP/kqmX/+/Tq///////////////////////8/Pv/6uHc/+bd150AAAAAAAAAAO3m4jXt5eHx9fHu///////68OT/7caQ//nu4f///////PXr/+vAif/glQD/35IA/+SlRv/qvYH/7sum/+7Lpv/pu4D/4qBE/92LAP/djAD/6bqI//z17P////////////////////////////Ls6f/n3df0593XLwAAAAAAAAAAAAAAAO3n44zu5+P/+vj3//////////////////////////////78//Tewv/os2n/4ZsA/9+RAP/ejAD/3YoA/96PAP/glwD/57Fu//PbwP///fz////////////////////////////49vT/6eDb/+nf2YkAAAAAAAAAAAAAAAAAAAAA7OnjEO7n48zw6uf//Pv7//////////////////////////////////78+f/57Nr/89zB//HVvP/x1bz/89zB//ns3P/+/fr//////////////////////////////////Pr5/+zl4P/p4NrM6ODYDgAAAAAAAAAAAAAAAAAAAAAAAAAA7+nlKe7n4+Dx6+j//Pv7//////////////////////////////////////////////////////////////////////////////////////////////////z7+v/u5+L/6eHb4evi2ywAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7+nlOu/o5OHx6+j/+vj3///////////////////////////////////////////////////////////////////////////////////////59/b/7ufi/+ri3eDr4906AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8OrmLO/p5czw6eb/9vLw//38/P/////////////////////////////////////////////////////////////////9/Pv/9PDt/+zl4P/r497M6+XeKQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8enpDvDq5onv6eX08ezo//by8P/7+vn//v7+//////////////////////////////////7+/v/7+fj/9fHv/+7o4//s5ODx7OTgjOvj3xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPHq5i/w6uWc7+nl7vDq5v/y7On/9PDt//bz8P/39PL/9/Ty//by8P/07+z/8Orn/+7n4//t5uHq7OXhmezl4TUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADw6+Ue8OrmYO/p5aDv6eXQ7+jl7O/o5P/u6OT/7ujk7O7n48zu5+Kc7efjY+zl5B0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/8AD//8AAP/8AAA/+AAAH/AAAA/gAAAHwAAAA8AAAAOAAAABgAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAGAAAABwAAAA8AAAAPgAAAH8AAAD/gAAB/8AAA//wAA///AA/8=")

Start-PopUp "Starting..."

#Check if WAUConfigurator is uptodate
Get-WAUConfiguratorLatestVersion

#Check if Winget is installed, and install if not
$null = Update-WinGet

#Get WinGet cmd
$Script:Winget = Get-WingetCmd

#Run WAUConfigurator
Close-PopUp
Start-InstallGUI
