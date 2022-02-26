<#
.SYNOPSIS
Configure Winget to daily update installed apps.

.DESCRIPTION
Install powershell scripts and scheduled task to daily run Winget upgrade and notify connected users.
Possible to exclude apps from auto-update
https://github.com/Romanitho/Winget-AutoUpdate

.PARAMETER Silent
Install Winget-AutoUpdate and prerequisites silently

.PARAMETER WingetUpdatePath
Specify Winget-AutoUpdate installation localtion. Default: C:\ProgramData\Winget-AutoUpdate\

.PARAMETER DoNotUpdate
Do not run Winget-autoupdate after installation. By default, Winget-AutoUpdate is run just after installation.

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -DoNotUpdate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)] [Alias('S')] [Switch] $Silent = $false,
    [Parameter(Mandatory=$False)] [Alias('Path')] [String] $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate",
    [Parameter(Mandatory=$False)] [Switch] $DoNotUpdate = $false
)


<# FUNCTIONS #>

function Check-Prerequisites{
    #Check if Visual C++ 2019 installed
    $app = "Microsoft Visual C++*2019*"
    $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $app}
    
    #If not installed, ask for installation
    if (!($path)){
        #If -silent option, force installation
        if ($Silent){
            $InstallApp = "y"
        }
        else{
            #Ask for installation
            while("y","n" -notcontains $InstallApp){
	            $InstallApp = Read-Host "[Prerequisite for Winget] Microsoft Visual C++ 2019 is not installed. Would you like to install it? [Y/N]"
            }
        }
        if ($InstallApp -eq "y"){
            try{
                if((Get-CimInStance Win32_OperatingSystem).OSArchitecture -like "*64*"){
                    $OSArch = "x64"
                }
                else{
                    $OSArch = "x86"
                }
                Write-host "Downloading VC_redist.$OSArch.exe..."
                $SourceURL = "https://aka.ms/vs/16/release/VC_redist.$OSArch.exe"
                $Installer = $WingetUpdatePath + "\VC_redist.$OSArch.exe"
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest $SourceURL -OutFile $Installer
                Write-host "Installing VC_redist.$OSArch.exe..."
                Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
                Remove-Item $Installer -ErrorAction Ignore
                Write-host "MS Visual C++ 2015-2019 installed successfully" -ForegroundColor Green
            }
            catch{
                Write-host "MS Visual C++ 2015-2019 installation failed." -ForegroundColor Red
                Start-Sleep 3
            }
        }
    }
    else{
        Write-Host "Prerequisites checked. OK" -ForegroundColor Green
    }
}

function Install-WingetAutoUpdate{
    try{
        #Check if previous version location exists and delete
        $OldWingetUpdatePath = $WingetUpdatePath.Replace("\Winget-AutoUpdate","\winget-update")
        if (Test-Path ($OldWingetUpdatePath)){
            Remove-Item $OldWingetUpdatePath -Force -Recurse
        }
        Get-ScheduledTask -TaskName "Winget Update" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False
        Get-ScheduledTask -TaskName "Winget Update Notify" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False

        #Copy files to location
        if (!(Test-Path $WingetUpdatePath)){
            New-Item -ItemType Directory -Force -Path $WingetUpdatePath
        }
        Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue

        # Set dummy regkeys for notification name and icon
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Application Update" /f | Out-Null
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification" /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f | Out-Null

        # Settings for the scheduled task for Updates
        $taskAction = New-ScheduledTaskAction –Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$($WingetUpdatePath)\winget-upgrade.ps1`""
        $taskTrigger1 = New-ScheduledTaskTrigger -AtLogOn
        $taskTrigger2 = New-ScheduledTaskTrigger  -Daily -At 6AM
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger2,$taskTrigger1
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -InputObject $task -Force

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction –Execute "wscript.exe" -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-notify.ps1`"`""
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -InputObject $task -Force

        Write-host "`nInstallation succeeded!" -ForegroundColor Green
        Start-sleep 1
        
        #Run Winget ?
        Start-WingetAutoUpdate
    }
    catch{
        Write-host "`nInstallation failed! Run me with admin rights" -ForegroundColor Red
        Start-sleep 1
        return $False
    }
}

function Start-WingetAutoUpdate{
    #If -DoNotUpdate is true, skip.
    if (!($DoNotUpdate)){
            #If -Silent, run Winget-AutoUpdate now
            if ($Silent){
                $RunWinget = "y"
            }
            #Ask for WingetAutoUpdate
            else{
                while("y","n" -notcontains $RunWinget){
	                $RunWinget = Read-Host "Start Winget-AutoUpdate now? [Y/N]"
                }
            }
        if ($RunWinget -eq "y"){
            try{
                Write-host "Running Winget-AutoUpdate..." -ForegroundColor Yellow
                Get-ScheduledTask -TaskName "Winget-AutoUpdate" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
            }
            catch{
                Write-host "Failed to run Winget-AutoUpdate..." -ForegroundColor Red
            }
        }
    }
    else{
        Write-host "Skip running Winget-AutoUpdate"
    }
}


<# MAIN #>

Write-host "###################################"
Write-host "#                                 #"
Write-host "#        Winget AutoUpdate        #"
Write-host "#                                 #"
Write-host "###################################`n"
Write-host "Installing to $WingetUpdatePath\"

Check-Prerequisites

Install-WingetAutoUpdate

Write-host "End of process."
Start-Sleep 3
