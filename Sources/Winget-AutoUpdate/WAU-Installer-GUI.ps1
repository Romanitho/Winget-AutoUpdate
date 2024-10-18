# import Appx module if the powershell version is 7/core
if ( $psversionTable.PSEdition -eq "core" ) {
    import-Module -name Appx -UseWIndowsPowershell -WarningAction:SilentlyContinue
}

#Get the Working Dir
$Script:WorkingDir = $PSScriptRoot


<# FUNCTIONS #>
. "$WorkingDir\functions\Get-WingetCmd.ps1"

#Function to start or update popup
Function Start-PopUp ($Message) {

    if (!$PopUpWindow) {

        #Create window
        $inputXML = @"
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:WAUConfigurator_v3"
        Title="WAU App Installer" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Width="280" MinHeight="130" SizeToContent="Height">
    <Grid>
        <TextBlock x:Name="PopUpLabel" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" Margin="20" TextAlignment="Center"/>
    </Grid>
</Window>
"@

        [xml]$XAML = ($inputXML -replace "x:N", "N")

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

    #Start Conversion of winget format to an array. Check if "-----" exists
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

    #Get header titles [without remove separator]
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
            #add formatted soft to list
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

function Start-Installations ($AppsToInstall) {

    #Run Winget-Install script
    Start-PopUp "Installing applications..."
    $WAUInstallPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\" -Name InstallLocation

    #Try with admin rights.
    try {
        Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File ""$WAUInstallPath\Winget-Install.ps1"" -AppIDs ""$AppsToInstall""" -Wait -Verb RunAs
    }
    catch {
        Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File ""$WAUInstallPath\Winget-Install.ps1"" -AppIDs ""$AppsToInstall""" -Wait
    }

    #Installs finished
    Start-PopUp "Done!"
    Start-Sleep 2
    #Close Popup
    Close-PopUp
}

function Start-Uninstallations ($AppsToUninstall) {
    #Run Winget-Install script
    Start-PopUp "Uninstalling applications..."
    $WAUInstallPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\" -Name InstallLocation

    #Run Winget-Install -Uninstall
    Start-Process "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File ""$WAUInstallPath\Winget-Install.ps1"" -AppIDs ""$AppsToUninstall"" -Uninstall" -Wait -Verb RunAs

    Close-PopUp
}

function Start-InstallGUI {

    ### FORM CREATION ###

    # GUI XAML file
    $inputXML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:local="clr-namespace:WAUConfigurator_v3"
    Title="WAU App Installer" Height="700" Width="540" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen">
<Grid>
    <Grid.Background>
        <SolidColorBrush Color="#FFF0F0F0"/>
    </Grid.Background>
    <TabControl x:Name="WAUConfiguratorTabControl" Margin="10,10,10,44">
        <TabItem x:Name="AppsTabPage" Header="Install Winget Apps">
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
    [xml]$XAML = ($inputXML -replace "x:N", "N")

    #Read the form
    $Reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $script:WAUAppInstallerGUI = [Windows.Markup.XamlReader]::Load($reader)

    #Store Form Objects In PowerShell
    $FormObjects = $xaml.SelectNodes("//*[@Name]")
    $FormObjects | ForEach-Object {
        Set-Variable -Name "$($_.Name)" -Value $WAUAppInstallerGUI.FindName($_.Name) -Scope Script
    }

    # Customization
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $WAUListOpenFile = New-Object System.Windows.Forms.OpenFileDialog
    $WAUListOpenFile.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $WAUAppInstallerGUI.Icon = $IconBase64


    ### FORM ACTIONS ###

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
                Start-Uninstallations "$($AppListBox.SelectedItems -join ",")"
                #$AppListBox.Items.Clear()
                while ($AppListBox.SelectedItems) {
                    $AppListBox.Items.Remove($AppListBox.SelectedItems[0])
                }
            }
            else {
                Start-PopUp "Please select apps to uninstall..."
                Start-Sleep 2
                Close-PopUp
            }
        }
    )

    $LogButton.add_click(
        {
            try {
                $LogPath = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\" -Name InstallLocatifon
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
                Start-Installations "$($AppListBox.Items -join ",")"
            }
            else {
                Start-PopUp "Add apps to install."
                Start-Sleep 2
                Close-PopUp
            }

        }
    )

    $CloseButton.add_click(
        {
            $WAUAppInstallerGUI.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $WAUAppInstallerGUI.Close()
        }
    )

    # Shows the form
    $Script:FormReturn = $WAUAppInstallerGUI.ShowDialog()
}


<# MAIN #>

#Load assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

#Pop "Starting..."
Start-PopUp "Starting..."

#Set config
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = "SilentlyContinue"
$Script:ErrorActionPreference = "SilentlyContinue"
$IconBase64 = [Convert]::FromBase64String("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")

#Get WinGet cmd
$Script:Winget = Get-WingetCmd

#Run WAUConfigurator
Close-PopUp
Start-InstallGUI
