<#
.SYNOPSIS
Install apps with Winget through Intune or SCCM.
(Can be used standalone.) - Deprecated in favor of Winget-AutoUpdate.

.DESCRIPTION
Allow to run Winget in System Context to install your apps.
(https://github.com/Romanitho/Winget-Install) - Deprecated in favor of Winget-AutoUpdate.

.PARAMETER AppIDs
Forward Winget App ID to install. For multiple apps, separate with ",". Case sensitive.

.PARAMETER Uninstall
To uninstall app. Works with AppIDs

.PARAMETER AllowUpgrade
To allow upgrade app if present. Works with AppIDs

.PARAMETER LogPath
Used to specify logpath. Default is same folder as Winget-Autoupdate project

.PARAMETER WAUWhiteList
Adds the app to the Winget-AutoUpdate White List. More info: https://github.com/Romanitho/Winget-AutoUpdate
If '-Uninstall' is used, it removes the app from WAU White List.

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -Uninstall

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -WAUWhiteList

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip,Notepad++.Notepad++ -LogPath "C:\temp\logs"

.EXAMPLE
.\winget-install.ps1 -AppIDs "7zip.7zip -v 22.00", "Notepad++.Notepad++"

.EXAMPLE
.\winget-install.ps1 -AppIDs "Notepad++.Notepad++" -AllowUpgrade
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, ParameterSetName = "AppIDs")] [String[]] $AppIDs,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall,
    [Parameter(Mandatory = $False)] [String] $LogPath,
    [Parameter(Mandatory = $False)] [Switch] $WAUWhiteList,
    [Parameter(Mandatory = $False)] [Switch] $AllowUpgrade
)


<# FUNCTIONS #>

#Include external Functions (check first if this script is a symlink or a real file)
$scriptItem = Get-Item -LiteralPath $MyInvocation.MyCommand.Definition
$realPath = if ($scriptItem.LinkType) {
    $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($scriptItem.Directory.FullName, $scriptItem.Target))
    Split-Path -Parent $targetPath
}
else {
    $scriptItem.DirectoryName
}

. "$realPath\functions\Install-Prerequisites.ps1"
. "$realPath\functions\Update-StoreApps.ps1"
. "$realPath\functions\Add-ScopeMachine.ps1"
. "$realPath\functions\Get-WingetCmd.ps1"
. "$realPath\functions\Write-ToLog.ps1"
. "$realPath\functions\Confirm-Installation.ps1"
. "$realPath\functions\Compare-SemVer.ps1"
. "$realPath\functions\Invoke-LogRotation.ps1"

#Check if App exists in Winget Repository
function Confirm-Exist ($AppID) {
    #Check is app exists in the winget repository
    $WingetApp = & $winget show --Id $AppID -e --accept-source-agreements -s winget | Out-String

    #Return if AppID exists
    if ($WingetApp -match [regex]::Escape($AppID)) {
        Write-ToLog "-> $AppID exists on Winget Repository." "Cyan" -Component "WinGet-Install"
        return $true
    }
    else {
        Write-ToLog "-> $AppID does not exist on Winget Repository! Check spelling." "Red" -Component "WinGet-Install"
        return $false
    }
}

#Check if install modifications exist in "mods" directory
function Test-ModsInstall ($AppID) {
    if (Test-Path "$Mods\$AppID-*") {
        if (Test-Path "$Mods\$AppID-preinstall.ps1") {
            $ModsPreInstall = "$Mods\$AppID-preinstall.ps1"
        } 
        if (Test-Path "$Mods\$AppID-override.txt") {
            $ModsOverride = (Get-Content "$Mods\$AppID-override.txt" -Raw).Trim()
        }
        if (Test-Path "$Mods\$AppID-custom.txt") {
            $ModsCustom = (Get-Content "$Mods\$AppID-custom.txt" -Raw).Trim()
        }
        if (Test-Path "$Mods\$AppID-install.ps1") {
            $ModsInstall = "$Mods\$AppID-install.ps1"
        }
        if (Test-Path "$Mods\$AppID-installed.ps1") {
            $ModsInstalled = "$Mods\$AppID-installed.ps1"
        }
    }

    return $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsInstall, $ModsInstalled
}

#Check if uninstall modifications exist in "mods" directory
function Test-ModsUninstall ($AppID) {
    if (Test-Path "$Mods\$AppID-*") {
        if (Test-Path "$Mods\$AppID-preuninstall.ps1") {
            $ModsPreUninstall = "$Mods\$AppID-preuninstall.ps1"
        } 
        if (Test-Path "$Mods\$AppID-uninstall.ps1") {
            $ModsUninstall = "$Mods\$AppID-uninstall.ps1"
        }
        if (Test-Path "$Mods\$AppID-uninstalled.ps1") {
            $ModsUninstalled = "$Mods\$AppID-uninstalled.ps1"
        }
    }

    return $ModsPreUninstall, $ModsUninstall, $ModsUninstalled
}

#Install function
function Install-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Installation $AppID
    if (!($IsInstalled) -or $AllowUpgrade ) {
        #Check if mods exist (or already exist) for preinstall/override/custom/install/installed
        $ModsPreInstall, $ModsOverride, $ModsCustom, $ModsInstall, $ModsInstalled = Test-ModsInstall $($AppID)

        #If PreInstall script exist
        if ($ModsPreInstall) {
            Write-ToLog "-> Modifications for $AppID before install are being applied..." "DarkYellow" -Component "WinGet-Install"
            & "$ModsPreInstall"
        }

        #Install App
        Write-ToLog "-> Installing $AppID..." "DarkYellow" -Component "WinGet-Install"
        if ($ModsOverride) {
            Write-ToLog "-> Arguments (overriding default): $ModsOverride" -Component "WinGet-Install" # Without -h (user overrides default)
            $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -s winget --override $ModsOverride" -split " "
        }
        elseif ($ModsCustom) {
            Write-ToLog "-> Arguments (customizing default): $ModsCustom" -Component "WinGet-Install" # With -h (user customizes default)
            $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -s winget -h --custom $ModsCustom" -split " "
        }
        else {
            $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -s winget -h $AppArgs" -split " "
        }

        Write-ToLog "-> Running: `"$Winget`" $WingetArgs" -Component "WinGet-Install"
        & "$Winget" $WingetArgs | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

        if ($ModsInstall) {
            Write-ToLog "-> Modifications for $AppID during install are being applied..." "DarkYellow" -Component "WinGet-Install"
            & "$ModsInstall"
        }

        #Check if install is ok
        $IsInstalled = Confirm-Installation $AppID
        if ($IsInstalled) {
            Write-ToLog "-> $AppID successfully installed." "Green" -Component "WinGet-Install"

            if ($ModsInstalled) {
                Write-ToLog "-> Modifications for $AppID after install are being applied..." "DarkYellow" -Component "WinGet-Install"
                & "$ModsInstalled"
            }

            #Add to WAU White List if set
            if ($WAUWhiteList) {
                Add-WAUWhiteList $AppID
            }
        }
        else {
            Write-ToLog "-> $AppID installation failed!" "Red" -Component "WinGet-Install"
        }
    }
    else {
        Write-ToLog "-> $AppID is already installed." "Cyan" -Component "WinGet-Install"
    }
}

#Uninstall function
function Uninstall-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Installation $AppID
    if ($IsInstalled) {
        #Check if mods exist (or already exist) for preuninstall/uninstall/uninstalled
        $ModsPreUninstall, $ModsUninstall, $ModsUninstalled = Test-ModsUninstall $AppID

        #If PreUninstall script exist
        if ($ModsPreUninstall) {
            Write-ToLog "-> Modifications for $AppID before uninstall are being applied..." "DarkYellow" -Component "WinGet-Install"
            & "$ModsPreUninstall"
        }

        #Uninstall App
        Write-ToLog "-> Uninstalling $AppID..." "DarkYellow" -Component "WinGet-Install"
        $WingetArgs = "uninstall --id $AppID -e --accept-source-agreements -h $AppArgs" -split " "
        Write-ToLog "-> Running: `"$Winget`" $WingetArgs" -Component "WinGet-Install"
        & "$Winget" $WingetArgs | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

        if ($ModsUninstall) {
            Write-ToLog "-> Modifications for $AppID during uninstall are being applied..." "DarkYellow" -Component "WinGet-Install"
            & "$ModsUninstall"
        }

        #Check if uninstall is ok
        $IsInstalled = Confirm-Installation $AppID
        if (!($IsInstalled)) {
            Write-ToLog "-> $AppID successfully uninstalled." "Green" -Component "WinGet-Install"
            if ($ModsUninstalled) {
                Write-ToLog "-> Modifications for $AppID after uninstall are being applied..." "DarkYellow" -Component "WinGet-Install"
                & "$ModsUninstalled"
            }

            #Remove from WAU White List if set
            if ($WAUWhiteList) {
                Remove-WAUWhiteList $AppID
            }
        }
        else {
            Write-ToLog "-> $AppID uninstall failed!" "Red" -Component "WinGet-Install"
        }
    }
    else {
        Write-ToLog "-> $AppID is not installed." "Cyan" -Component "WinGet-Install"
    }
}

#Function to Add app to WAU white list
function Add-WAUWhiteList ($AppID) {
    #Check if WAU default install path is defined
    if ($WAUInstallLocation) {
        $WhiteList = "$WAUInstallLocation\included_apps.txt"
        #Create included_apps.txt if it doesn't exist
        if (!(Test-Path $WhiteList)) {
            New-Item -ItemType File -Path $WhiteList -Force -ErrorAction SilentlyContinue
        }
        Write-ToLog "-> Add $AppID to WAU included_apps.txt" -Component "WinGet-Install"
        #Add App to "included_apps.txt"
        Add-Content -Path $WhiteList -Value "`n$AppID" -Force
        #Remove duplicate and blank lines
        $file = Get-Content $WhiteList | Select-Object -Unique | Where-Object { $_.trim() -ne "" } | Sort-Object
        $file | Out-File $WhiteList
    }
}

#Function to Remove app from WAU white list
function Remove-WAUWhiteList ($AppID) {
    #Check if WAU default install path exists
    $WhiteList = "$WAUInstallLocation\included_apps.txt"
    if (Test-Path $WhiteList) {
        Write-ToLog "-> Remove $AppID from WAU included_apps.txt" -Component "WinGet-Install"
        #Remove app from list
        $file = Get-Content $WhiteList | Where-Object { $_ -ne "$AppID" }
        $file | Out-File $WhiteList
    }
}

# Function to check log file status
function Test-LogFileStatus {
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

    #LogRotation
    [bool]$LogRotate = Invoke-LogRotation $LogFile $MaxLogFiles $MaxLogSize;
    if ($false -eq $LogRotate) {
        Write-ToLog "An Exception occurred during Log Rotation..." "Red" -Component "WinGet-Install"
    }
}

<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}

#Config console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

#Check if current process is elevated (System or admin user)
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$Script:IsElevated = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#Get WAU Installed location
$WAURegKey = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate\"
$Script:WAUInstallLocation = Get-ItemProperty $WAURegKey -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InstallLocation
# Use the Working Dir (even if it is from a symlink)
$Mods = "$realPath\mods"

#Log file & LogPath initialization
if ($IsElevated) {
    if (!($LogPath)) {
        #If LogPath is not set, get WAU log path
        if ($WAUInstallLocation) {
            $LogPath = "$WAUInstallLocation\Logs"
        }
        else {
            #Else, set a default one
            $LogPath = "$env:ProgramData\Winget-AutoUpdate\Logs"
        }
    }
    $Script:LogFile = "$LogPath\install.log"
}
else {
    if (!($LogPath)) {
        $LogPath = "C:\Users\$env:UserName\AppData\Roaming\Winget-AutoUpdate\Logs"
    }
    $Script:LogFile = "$LogPath\install_$env:UserName.log"
}

#Logs initialization
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
}

# Test the status of the log files
Test-LogFileStatus

#Log Header
if ($Uninstall) {
    Write-ToLog "NEW UNINSTALL REQUEST" -LogColor "Magenta" -IsHeader -Component "WinGet-Install"
}
else {
    Write-ToLog "NEW INSTALL REQUEST" -LogColor "Magenta" -IsHeader -Component "WinGet-Install"
}

if ($IsElevated -eq $True) {
    Write-ToLog "Running with admin rights.`n" -Component "WinGet-Install"

    #Check/install prerequisites
    Install-Prerequisites

    #Reload Winget command
    $Script:Winget = Get-WingetCmd

    #Run Scope Machine function
    Add-ScopeMachine
}
else {
    Write-ToLog "Running without admin rights.`n" -Component "WinGet-Install"

    #Get Winget command
    $Script:Winget = Get-WingetCmd
}

if ($Winget) {
    #Put apps in an array
    $AppIDsArray = $AppIDs -split ","
    Write-Host ""

    #Run install or uninstall for all apps
    foreach ($App_Full in $AppIDsArray) {
        #Split AppID and Custom arguments
        $AppID, $AppArgs = ($App_Full.Trim().Split(" ", 2))

        #Log current App
        Write-ToLog "Start $AppID processing..." "Blue" -Component "WinGet-Install"

        #Install or Uninstall command
        if ($Uninstall) {
            Uninstall-App $AppID $AppArgs
        }
        else {
            #Check if app exists on Winget Repo
            $Exists = Confirm-Exist $AppID
            if ($Exists) {
                #Install
                Install-App $AppID $AppArgs
            }
        }

        #Log current App
        Write-ToLog "$AppID processing finished!`n" "Blue" -Component "WinGet-Install"
        Start-Sleep 1
    }
}

Write-ToLog "END REQUEST" "Magenta" -IsHeader -Component "WinGet-Install"
Start-Sleep 3
