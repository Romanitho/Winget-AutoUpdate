<#
      .SYNOPSIS
      Configure Winget to daily update installed apps.

      .DESCRIPTION
      Install powershell scripts and scheduled task to daily run Winget upgrade and notify connected users.
      Posibility to exclude apps from auto-update
      https://github.com/Romanitho/Winget-AutoUpdate

      .PARAMETER Silent
      Install Winget-AutoUpdate and prerequisites silently

      .PARAMETER MaxLogFiles
      Specify number of allowed log files (Default is 3 of 0-99: Setting MaxLogFiles to 0 don't delete any old archived log files, 1 keeps the original one and just let it grow)

      .PARAMETER MaxLogSize
      Specify the size of the log file in bytes before rotating. (Default is 1048576 = 1 MB)

      .PARAMETER WingetUpdatePath
      Specify Winget-AutoUpdate installation localtion. Default: C:\ProgramData\Winget-AutoUpdate\

      .PARAMETER DoNotUpdate
      Do not run Winget-AutoUpdate after installation. By default, Winget-AutoUpdate is run just after installation.

      .PARAMETER DisableWAUAutoUpdate
      Disable Winget-AutoUpdate update checking. By default, WAU auto update if new version is available on Github.

      .PARAMETER UseWhiteList
      Use White List instead of Black List. This setting will not create the "exclude_apps.txt" but "include_apps.txt"

      .PARAMETER ListPath
      Get Black/White List from Path (URL/UNC/GPO/Local)

      .PARAMETER ModsPath
      Get mods from Path (URL/UNC/Local/AzureBlob)

      .PARAMETER AzureBlobURL
      Set the Azure Storage Blob URL including the SAS token. The token requires at a minimum 'Read' and 'List' permissions. It is recommended to set this at the container level

      .PARAMETER Uninstall
      Remove scheduled tasks and scripts.

      .PARAMETER NoClean
      Keep critical files when installing/uninstalling

      .PARAMETER DesktopShortcut
      Create a shortcut for user interaction on the Desktop to run task "Winget-AutoUpdate"

      .PARAMETER StartMenuShortcut
      Create shortcuts for user interaction in the Start Menu to run task "Winget-AutoUpdate", open Logs and Web Help

      .PARAMETER NotificationLevel
      Specify the Notification level: Full (Default, displays all notification), SuccessOnly (Only displays notification for success) or None (Does not show any popup).

      .PARAMETER UpdatesAtLogon
      Set WAU to run at user logon.

      .PARAMETER UpdatesInterval
      Specify the update frequency: Daily (Default), BiDaily, Weekly, BiWeekly, Monthly or Never

      .PARAMETER UpdatesAtTime
      Specify the time of the update interval execution time. Default 6AM

      .PARAMETER RunOnMetered
      Run WAU on metered connection. Default No.

      .PARAMETER InstallUserContext
      Install WAU with system and user context executions

      .PARAMETER BypassListForUsers
      Configure WAU to bypass the Black/White list when run in user context. Applications installed in system context will be ignored under user context.

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -DoNotUpdate -MaxLogFiles 4 -MaxLogSize 2097152

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -UseWhiteList

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -ListPath https://www.domain.com/WAULists -StartMenuShortcut -UpdatesInterval BiDaily

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -ModsPath https://www.domain.com/WAUMods -DesktopShortcut -UpdatesInterval Weekly

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -UpdatesAtLogon -UpdatesInterval Weekly

      .EXAMPLE
      .\Winget-AutoUpdate-Install.ps1 -Silent -Uninstall -NoClean

#>

[CmdletBinding()]
param(
   [Alias('S')] [Switch] $Silent = $false,
   [Alias('Path')] [String] $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate",
   [Alias('List')] [String] $ListPath,
   [Alias('Mods')] [String] $ModsPath,
   [Alias('AzureBlobURL')] [String] $AzureBlobSASURL,
   [Switch] $DoNotUpdate = $false,
   [Switch] $DisableWAUAutoUpdate = $false,
   [Switch] $RunOnMetered = $false,
   [Switch] $Uninstall = $false,
   [Switch] $NoClean = $false,
   [Switch] $DesktopShortcut = $false,
   [Switch] $StartMenuShortcut = $false,
   [Switch] $UseWhiteList = $false,
   [ValidateSet('Full', 'SuccessOnly', 'None')] [String] $NotificationLevel = 'Full',
   [Switch] $UpdatesAtLogon = $false,
   [ValidateSet('Daily', 'BiDaily', 'Weekly', 'BiWeekly', 'Monthly', 'Never')] [String] $UpdatesInterval = 'Daily',
   [DateTime] $UpdatesAtTime = ('06am'),
   [Switch] $BypassListForUsers = $false,
   [Switch] $InstallUserContext = $false,
   [ValidateRange(0, 99)] [int] $MaxLogFiles = 3,
   [long] $MaxLogSize = 1048576 # in bytes, default is 1048576 = 1 MB
)


<# FUNCTIONS #>

function Install-Prerequisites 
{
   Write-Host -Object "`nChecking prerequisites..." -ForegroundColor Yellow

   #Check if Visual C++ 2019 or 2022 installed
   $Visual2019 = 'Microsoft Visual C++ 2015-2019 Redistributable*'
   $Visual2022 = 'Microsoft Visual C++ 2015-2022 Redistributable*'
   $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object -FilterScript {
      $_.GetValue('DisplayName') -like $Visual2019 -or $_.GetValue('DisplayName') -like $Visual2022 
   }

   #If not installed, ask for installation
   if (!($path)) 
   {
      #If -silent option, force installation
      if ($Silent) 
      {
         $InstallApp = 1
      }
      else 
      {
         #Ask for installation
         $MsgBoxTitle = 'Winget Prerequisites'
         $MsgBoxContent = 'Microsoft Visual C++ 2015-2022 is required. Would you like to install it?'
         $MsgBoxTimeOut = 60
         $MsgBoxReturn = (New-Object -ComObject 'Wscript.Shell').Popup($MsgBoxContent, $MsgBoxTimeOut, $MsgBoxTitle, 4 + 32)
         if ($MsgBoxReturn -ne 7) 
         {
            $InstallApp = 1
         }
         else 
         {
            $InstallApp = 0
         }
      }
      #Install if approved
      if ($InstallApp -eq 1) 
      {
         try 
         {
            if ((Get-CimInstance Win32_OperatingSystem).OSArchitecture -like '*64*') 
            {
               $OSArch = 'x64'
            }
            else 
            {
               $OSArch = 'x86'
            }
            Write-Host -Object "-> Downloading VC_redist.$OSArch.exe..."
            $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
            $Installer = $WingetUpdatePath + "\VC_redist.$OSArch.exe"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $SourceURL -UseBasicParsing -OutFile (New-Item -Path $Installer -Force)
            Write-Host -Object "-> Installing VC_redist.$OSArch.exe..."
            Start-Process -FilePath $Installer -ArgumentList '/quiet /norestart' -Wait
            Remove-Item $Installer -ErrorAction Ignore
            Write-Host -Object 'MS Visual C++ 2015-2022 installed successfully' -ForegroundColor Green
         }
         catch 
         {
            Write-Host -Object 'MS Visual C++ 2015-2022 installation failed.' -ForegroundColor Red
            Start-Sleep -Seconds 3
         }
      }
      else 
      {
         Write-Host -Object '-> MS Visual C++ 2015-2022 will not be installed.' -ForegroundColor Magenta
      }
   }
   else 
   {
      Write-Host -Object 'Prerequisites checked. OK' -ForegroundColor Green
   }
}

function Install-WinGet 
{
   Write-Host -Object "`nChecking if Winget is installed" -ForegroundColor Yellow

   #Check Package Install
   $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object -FilterScript {
      $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' 
   }

   #Current: v1.5.2201 = 1.20.2201.0 = 2023.808.2243.0
   If ([Version]$TestWinGet.Version -ge '2023.808.2243.0') 
   {
      Write-Host -Object 'Winget is Installed' -ForegroundColor Green
   }
   Else 
   {
      Write-Host -Object '-> Winget is not installed:'

      #Check if $WingetUpdatePath exist
      if (!(Test-Path $WingetUpdatePath)) 
      {
         $null = New-Item -ItemType Directory -Force -Path $WingetUpdatePath
      }

      #Downloading and Installing Dependencies in SYSTEM context
      if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.7')) 
      {
         Write-Host -Object '-> Downloading Microsoft.UI.Xaml.2.7...'
         $UiXamlUrl = 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.0'
         $UiXamlZip = "$WingetUpdatePath\Microsoft.UI.XAML.2.7.zip"
         Invoke-RestMethod -Uri $UiXamlUrl -OutFile $UiXamlZip
         Expand-Archive -Path $UiXamlZip -DestinationPath "$WingetUpdatePath\extracted" -Force
         try 
         {
            Write-Host -Object '-> Installing Microsoft.UI.Xaml.2.7...'
            $null = Add-AppxProvisionedPackage -Online -PackagePath "$WingetUpdatePath\extracted\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx" -SkipLicense
            Write-Host -Object 'Microsoft.UI.Xaml.2.7 installed successfully' -ForegroundColor Green
         }
         catch 
         {
            Write-Host -Object 'Failed to intall Wicrosoft.UI.Xaml.2.7...' -ForegroundColor Red
         }
         Remove-Item -Path $UiXamlZip -Force
         Remove-Item -Path "$WingetUpdatePath\extracted" -Force -Recurse
      }

      if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop')) 
      {
         Write-Host -Object '-> Downloading Microsoft.VCLibs.140.00.UWPDesktop...'
         $VCLibsUrl = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
         $VCLibsFile = "$WingetUpdatePath\Microsoft.VCLibs.x64.14.00.Desktop.appx"
         Invoke-RestMethod -Uri $VCLibsUrl -OutFile $VCLibsFile
         try 
         {
            Write-Host -Object '-> Installing Microsoft.VCLibs.140.00.UWPDesktop...'
            $null = Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense
            Write-Host -Object 'Microsoft.VCLibs.140.00.UWPDesktop installed successfully' -ForegroundColor Green
         }
         catch 
         {
            Write-Host -Object 'Failed to intall Microsoft.VCLibs.140.00.UWPDesktop...' -ForegroundColor Red
         }
         Remove-Item -Path $VCLibsFile -Force
      }

      #Download WinGet MSIXBundle
      Write-Host -Object '-> Downloading Winget MSIXBundle for App Installer...'
      $WinGetURL = 'https://github.com/microsoft/winget-cli/releases/download/v1.5.2201/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
      $WebClient = New-Object -TypeName System.Net.WebClient
      $WebClient.DownloadFile($WinGetURL, "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")

      #Install WinGet MSIXBundle in SYSTEM context
      try 
      {
         Write-Host -Object '-> Installing Winget MSIXBundle for App Installer...'
         $null = Add-AppxProvisionedPackage -Online -PackagePath "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense
         Write-Host -Object 'Winget MSIXBundle for App Installer installed successfully' -ForegroundColor Green
      }
      catch 
      {
         Write-Host -Object 'Failed to intall Winget MSIXBundle for App Installer...' -ForegroundColor Red
      }

      #Remove WinGet MSIXBundle
      Remove-Item -Path "$WingetUpdatePath\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue
   }
}

function Install-WingetAutoUpdate 
{
   Write-Host -Object "`nInstalling WAU..." -ForegroundColor Yellow

   try 
   {
      #Copy files to location (and clean old install)
      if (!(Test-Path $WingetUpdatePath)) 
      {
         $null = New-Item -ItemType Directory -Force -Path $WingetUpdatePath
      }
      else 
      {
         if (!$NoClean) 
         {
            Remove-Item -Path "$WingetUpdatePath\*" -Exclude *.log -Recurse -Force
         }
         else 
         {
            #Keep critical files
            Get-ChildItem -Path $WingetUpdatePath -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force
         }
      }
      Copy-Item -Path "$PSScriptRoot\Winget-AutoUpdate\*" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue

      #White List or Black List apps
      if ($UseWhiteList) 
      {
         if (!$NoClean) 
         {
            if ((Test-Path -Path "$PSScriptRoot\included_apps.txt")) 
            {
               Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else 
            {
               if (!$ListPath) 
               {
                  $null = New-Item -Path $WingetUpdatePath -Name 'included_apps.txt' -ItemType 'file' -ErrorAction SilentlyContinue
               }
            }
         }
         elseif (!(Test-Path -Path "$WingetUpdatePath\included_apps.txt")) 
         {
            if ((Test-Path -Path "$PSScriptRoot\included_apps.txt")) 
            {
               Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else 
            {
               if (!$ListPath) 
               {
                  $null = New-Item -Path $WingetUpdatePath -Name 'included_apps.txt' -ItemType 'file' -ErrorAction SilentlyContinue
               }
            }
         }
      }
      else 
      {
         if (!$NoClean) 
         {
            Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
         }
         elseif (!(Test-Path -Path "$WingetUpdatePath\excluded_apps.txt")) 
         {
            Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $WingetUpdatePath -Recurse -Force -ErrorAction SilentlyContinue
         }
      }

      # Set dummy regkeys for notification name and icon
      $null = & "$env:windir\system32\reg.exe" add 'HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification' /v DisplayName /t REG_EXPAND_SZ /d 'Application Update' /f
      $null = & "$env:windir\system32\reg.exe" add 'HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification' /v IconUri /t REG_EXPAND_SZ /d %SystemRoot%\system32\@WindowsUpdateToastIcon.png /f

      # Settings for the scheduled task for Updates
      $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($WingetUpdatePath)\winget-upgrade.ps1`""
      $taskTriggers = @()
      if ($UpdatesAtLogon) 
      {
         $taskTriggers += New-ScheduledTaskTrigger -AtLogOn
      }
      if ($UpdatesInterval -eq 'Daily') 
      {
         $taskTriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime
      }
      elseif ($UpdatesInterval -eq 'BiDaily') 
      {
         $taskTriggers += New-ScheduledTaskTrigger -Daily -At $UpdatesAtTime -DaysInterval 2
      }
      elseif ($UpdatesInterval -eq 'Weekly') 
      {
         $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2
      }
      elseif ($UpdatesInterval -eq 'BiWeekly') 
      {
         $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2
      }
      elseif ($UpdatesInterval -eq 'Monthly') 
      {
         $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4
      }
      $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
      $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

      # Set up the task, and register it
      if ($taskTriggers) 
      {
         $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTriggers
      }
      else 
      {
         $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
      }
        
      $null = Register-ScheduledTask -TaskName 'Winget-AutoUpdate' -InputObject $task -Force

      if ($InstallUserContext) 
      {
         # Settings for the scheduled task in User context
         $taskAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-upgrade.ps1`"`""
         $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
         $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

         # Set up the task for user apps
         $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
         $null = Register-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -InputObject $task -Force
      }

      # Settings for the scheduled task for Notifications
      $taskAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\winget-notify.ps1`"`""
      $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
      $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00

      # Set up the task, and register it
      $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
      $null = Register-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -InputObject $task -Force

      #Set task readable/runnable for all users
      $scheduler = New-Object -ComObject 'Schedule.Service'
      $scheduler.Connect()
      $task = $scheduler.GetFolder('').GetTask('Winget-AutoUpdate')
      $sec = $task.GetSecurityDescriptor(0xF)
      $sec = $sec + '(A;;GRGX;;;AU)'
      $task.SetSecurityDescriptor($sec, 0)

      # Configure Reg Key
      $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate'
      $null = New-Item $regPath -Force
      $null = New-ItemProperty $regPath -Name DisplayName -Value 'Winget-AutoUpdate (WAU)' -Force
      $null = New-ItemProperty $regPath -Name DisplayIcon -Value 'C:\Windows\System32\shell32.dll,-16739' -Force
      $null = New-ItemProperty $regPath -Name DisplayVersion -Value $WAUVersion -Force
      $null = New-ItemProperty $regPath -Name InstallLocation -Value $WingetUpdatePath -Force
      $null = New-ItemProperty $regPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WingetUpdatePath\WAU-Uninstall.ps1`"" -Force
      $null = New-ItemProperty $regPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WingetUpdatePath\WAU-Uninstall.ps1`"" -Force
      $null = New-ItemProperty $regPath -Name NoModify -Value 1 -Force
      $null = New-ItemProperty $regPath -Name NoRepair -Value 1 -Force
      $null = New-ItemProperty $regPath -Name Publisher -Value 'Romanitho' -Force
      $null = New-ItemProperty $regPath -Name URLInfoAbout -Value 'https://github.com/Romanitho/Winget-AutoUpdate' -Force
      $null = New-ItemProperty $regPath -Name WAU_NotificationLevel -Value $NotificationLevel -Force
      if ($WAUVersion -match '-')
      {
         $null = New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force
      }
      else 
      {
         $null = New-ItemProperty $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force
      }
      $null = New-ItemProperty $regPath -Name WAU_PostUpdateActions -Value 0 -PropertyType DWord -Force
      $null = New-ItemProperty $regPath -Name WAU_MaxLogFiles -Value $MaxLogFiles -PropertyType DWord -Force
      $null = New-ItemProperty $regPath -Name WAU_MaxLogSize -Value $MaxLogSize -PropertyType DWord -Force
      if ($DisableWAUAutoUpdate) 
      {
         $null = New-ItemProperty $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force
      }
      if ($UseWhiteList) 
      {
         $null = New-ItemProperty $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force
      }
      if (!$RunOnMetered) 
      {
         $null = New-ItemProperty $regPath -Name WAU_DoNotRunOnMetered -Value 1 -PropertyType DWord -Force
      }
      if ($ListPath) 
      {
         $null = New-ItemProperty $regPath -Name WAU_ListPath -Value $ListPath -Force
      }
      if ($ModsPath) 
      {
         $null = New-ItemProperty $regPath -Name WAU_ModsPath -Value $ModsPath -Force
      }
      if ($AzureBlobSASURL) 
      {
         $null = New-ItemProperty $regPath -Name WAU_AzureBlobSASURL -Value $AzureBlobSASURL -Force
      }
      if ($BypassListForUsers) 
      {
         $null = New-ItemProperty $regPath -Name WAU_BypassListForUsers -Value 1 -PropertyType DWord -Force
      }

      #Log file and symlink initialization
      . "$WingetUpdatePath\functions\Start-Init.ps1"
      Start-Init

      #Security check
      Write-Host -Object "`nChecking Mods Directory:" -ForegroundColor Yellow
      . "$WingetUpdatePath\functions\Invoke-ModsProtect.ps1"
      $Protected = Invoke-ModsProtect "$WingetUpdatePath\mods"
      if ($Protected -eq $True) 
      {
         Write-Host -Object "The mods directory is now secured!`n" -ForegroundColor Green
      }
      elseif ($Protected -eq $false) 
      {
         Write-Host -Object "The mods directory was already secured!`n" -ForegroundColor Green
      }
      else 
      {
         Write-Host -Object "Error: The mods directory couldn't be verified as secured!`n" -ForegroundColor Red
      }

      #Create Shortcuts
      if ($StartMenuShortcut) 
      {
         if (!(Test-Path -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) 
         {
            $null = New-Item -ItemType Directory -Force -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)"
         }
         Add-Shortcut 'wscript.exe' "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Check for updated Apps.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" 'Manual start of Winget-AutoUpdate (WAU)...'
         Add-Shortcut 'wscript.exe' "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Open logs.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`" -Logs`"" "${env:SystemRoot}\System32\shell32.dll,-16763" 'Open existing WAU logs...'
         Add-Shortcut 'wscript.exe' "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)\WAU - Web Help.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`" -Help`"" "${env:SystemRoot}\System32\shell32.dll,-24" 'Help for WAU...'
      }

      if ($DesktopShortcut) 
      {
         Add-Shortcut 'wscript.exe' "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" "`"$($WingetUpdatePath)\Invisible.vbs`" `"powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`"`"$($WingetUpdatePath)\user-run.ps1`"`"" "${env:SystemRoot}\System32\shell32.dll,-16739" 'Manual start of Winget-AutoUpdate (WAU)...'
      }

      Write-Host -Object 'WAU Installation succeeded!' -ForegroundColor Green
      Start-Sleep -Seconds 1

      #Run Winget ?
      Start-WingetAutoUpdate
   }
   catch 
   {
      Write-Host -Object 'WAU Installation failed! Run me with admin rights' -ForegroundColor Red
      Start-Sleep -Seconds 1
      return $false
   }
}

function Uninstall-WingetAutoUpdate 
{
   Write-Host -Object "`nUninstalling WAU..." -ForegroundColor Yellow

   try 
   {
      #Get registry install location
      $InstallLocation = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\' -Name InstallLocation

      #Check if installed location exists and delete
      if (Test-Path ($InstallLocation)) 
      {
         if (!$NoClean) 
         {
            Remove-Item $InstallLocation -Force -Recurse
            if (Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log") 
            {
               $null = Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log") 
            {
               $null = Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -Force -ErrorAction SilentlyContinue
            }
         }
         else 
         {
            #Keep critical files
            Get-ChildItem -Path $InstallLocation -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force
         }
         Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
         Get-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
         Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
         $null = & "$env:windir\system32\reg.exe" delete 'HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification' /f
         $null = & "$env:windir\system32\reg.exe" delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate' /f

         if ((Test-Path -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) 
         {
            $null = Remove-Item -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" -Recurse -Force
         }

         if ((Test-Path -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk")) 
         {
            $null = Remove-Item -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" -Force
         }

         Write-Host -Object 'Uninstallation succeeded!' -ForegroundColor Green
         Start-Sleep -Seconds 1
      }
      else 
      {
         Write-Host -Object "$InstallLocation not found! Uninstallation failed!" -ForegroundColor Red
      }
   }
   catch 
   {
      Write-Host -Object 'Uninstallation failed! Run as admin ?' -ForegroundColor Red
      Start-Sleep -Seconds 1
   }
}

function Start-WingetAutoUpdate 
{
   #If -DoNotUpdate is true, skip.
   if (!($DoNotUpdate)) 
   {
      #If -Silent, run Winget-AutoUpdate now
      if ($Silent) 
      {
         $RunWinget = 1
      }
      #Ask for WingetAutoUpdate
      else 
      {
         $MsgBoxTitle = 'Winget-AutoUpdate'
         $MsgBoxContent = 'Would you like to run Winget-AutoUpdate now?'
         $MsgBoxTimeOut = 60
         $MsgBoxReturn = (New-Object -ComObject 'Wscript.Shell').Popup($MsgBoxContent, $MsgBoxTimeOut, $MsgBoxTitle, 4 + 32)
         if ($MsgBoxReturn -ne 7) 
         {
            $RunWinget = 1
         }
         else 
         {
            $RunWinget = 0
         }
      }
      if ($RunWinget -eq 1) 
      {
         try 
         {
            Write-Host -Object "`nRunning Winget-AutoUpdate..." -ForegroundColor Yellow
            Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
            while ((Get-ScheduledTask -TaskName 'Winget-AutoUpdate').State -ne 'Ready') 
            {
               Start-Sleep -Seconds 1
            }
         }
         catch 
         {
            Write-Host -Object 'Failed to run Winget-AutoUpdate...' -ForegroundColor Red
         }
      }
   }
   else 
   {
      Write-Host -Object 'Skip running Winget-AutoUpdate'
   }
}

function Add-Shortcut 
{
   [CmdletBinding()]
   param
   (
      $Target,

      $Shortcut,

      $Arguments,

      $Icon,

      $Description
   )
   $WScriptShell = New-Object -ComObject WScript.Shell
   $Shortcut = $WScriptShell.CreateShortcut($Shortcut)
   $Shortcut.TargetPath = $Target
   $Shortcut.Arguments = $Arguments
   $Shortcut.IconLocation = $Icon
   $Shortcut.Description = $Description
   $Shortcut.Save()
}


<# APP INFO #>

$WAUVersion = Get-Content -Path "$PSScriptRoot\Winget-AutoUpdate\Version.txt" -ErrorAction SilentlyContinue


<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne 'ARM64') 
{
   if (Test-Path -Path "$($env:windir)\SysNative\WindowsPowerShell\v1.0\powershell.exe") 
   {
      Start-Process -FilePath "$($env:windir)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -NoNewWindow -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
      Exit $lastexitcode
   }
}

Write-Host -Object "`n"
Write-Host -Object "`t        888       888        d8888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888   o   888       d88888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888  d8b  888      d88P888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888 d888b 888     d88P 888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888d88888b888    d88P  888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        88888P Y88888   d88P   888  888     888" -ForegroundColor Cyan
Write-Host -Object "`t        8888P   Y8888  d88P    888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888P     Y888 d88P     888   Y8888888P`n" -ForegroundColor Magenta
Write-Host -Object "`t                 Winget-AutoUpdate $WAUVersion`n" -ForegroundColor Cyan
Write-Host -Object "`t     https://github.com/Romanitho/Winget-AutoUpdate`n" -ForegroundColor Magenta
Write-Host -Object "`t________________________________________________________`n`n"

if (!$Uninstall) 
{
   Write-Host -Object "Installing WAU to $WingetUpdatePath\"
   Install-Prerequisites
   Install-WinGet
   Install-WingetAutoUpdate
}
else 
{
   Write-Host -Object 'Uninstalling WAU...'
   Uninstall-WingetAutoUpdate
}

Remove-Item -Path "$WingetUpdatePath\Version.txt" -Force
Write-Host -Object "`nEnd of process." -ForegroundColor Cyan
Start-Sleep -Seconds 3
