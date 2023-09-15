# Function to make actions after WAU update

function Invoke-PostUpdateActions 
{
   # log
   Write-ToLog -LogMsg 'Running Post Update actions:' -LogColor 'yellow'

   # Check if Intune Management Extension Logs folder and WAU-updates.log exists, make symlink
   if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs" -ErrorAction SilentlyContinue) -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ErrorAction SilentlyContinue)) 
   {
      Write-ToLog -LogMsg '-> Creating SymLink for log file in Intune Management Extension log folder' -LogColor 'yellow'
      $null = New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue
   }
    
   # Check if Intune Management Extension Logs folder and WAU-install.log exists, make symlink
   if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs" -ErrorAction SilentlyContinue) -and (Test-Path -Path ('{0}\logs\install.log' -f $WorkingDir) -ErrorAction SilentlyContinue) -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ErrorAction SilentlyContinue)) 
   {
      Write-Host -Object "`nCreating SymLink for log file (WAU-install) in Intune Management Extension log folder" -ForegroundColor Yellow
      $null = (New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ItemType SymbolicLink -Value ('{0}\logs\install.log' -f $WorkingDir) -Force -Confirm:$False -ErrorAction SilentlyContinue)
   }

   Write-ToLog -LogMsg '-> Checking prerequisites...' -LogColor 'yellow'

   # Check if Visual C++ 2019 or 2022 installed
   $Visual2019 = 'Microsoft Visual C++ 2015-2019 Redistributable*'
   $Visual2022 = 'Microsoft Visual C++ 2015-2022 Redistributable*'
   $path = (Get-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object -FilterScript {
         $_.GetValue('DisplayName') -like $Visual2019 -or $_.GetValue('DisplayName') -like $Visual2022
   })

   # If not installed, install
   if (!($path)) 
   {
      try 
      {
         if ((Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture -like '*64*') 
         {
            $OSArch = 'x64'
         }
         else 
         {
            $OSArch = 'x86'
         }
            
         Write-ToLog -LogMsg ('-> Downloading VC_redist.{0}.exe...' -f $OSArch)
         $SourceURL = ('https://aka.ms/vs/17/release/VC_redist.{0}.exe' -f $OSArch)
         $Installer = ('{0}\VC_redist.{1}.exe' -f $WAUConfig.InstallLocation, $OSArch)
         $ProgressPreference = 'SilentlyContinue'
         $null = (Invoke-WebRequest -Uri $SourceURL -UseBasicParsing -OutFile (New-Item -Path $Installer -Force))
         Write-ToLog -LogMsg ('-> Installing VC_redist.{0}.exe...' -f $OSArch)
         Start-Process -FilePath $Installer -ArgumentList '/quiet /norestart' -Wait
         Remove-Item -Path $Installer -ErrorAction Ignore
         Write-ToLog -LogMsg '-> MS Visual C++ 2015-2022 installed successfully' -LogColor 'green'
      }
      catch 
      {
         Write-ToLog -LogMsg '-> MS Visual C++ 2015-2022 installation failed.' -LogColor 'red'
      }
   }
   else 
   {
      Write-ToLog -LogMsg '-> Prerequisites checked. OK' -LogColor 'green'
   }

   # Check Package Install
   Write-ToLog -LogMsg '-> Checking if Winget is installed/up to date' -LogColor 'yellow'
   $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object -FilterScript {
      $_.DisplayName -eq 'Microsoft.DesktopAppInstaller'
   }

   # Current: v1.5.2201 = 1.20.2201.0 = 2023.808.2243.0
   If ([Version]$TestWinGet.Version -ge '2023.808.2243.0') 
   {
      Write-ToLog -LogMsg '-> WinGet is Installed/up to date' -LogColor 'green'
   }
   Else 
   {
      # Download WinGet MSIXBundle
      Write-ToLog -LogMsg '-> Not installed/up to date. Downloading WinGet...'
      $WinGetURL = 'https://github.com/microsoft/winget-cli/releases/download/v1.5.2201/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
      $WebClient = New-Object -TypeName System.Net.WebClient
      $WebClient.DownloadFile($WinGetURL, ('{0}\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -f $WAUConfig.InstallLocation))

      # Install WinGet MSIXBundle
      try 
      {
         Write-ToLog -LogMsg '-> Installing Winget MSIXBundle for App Installer...'
         $null = Add-AppxProvisionedPackage -Online -PackagePath ('{0}\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -f $WAUConfig.InstallLocation) -SkipLicense
         Write-ToLog -LogMsg '-> Installed Winget MSIXBundle for App Installer' -LogColor 'green'
      }
      catch 
      {
         Write-ToLog -LogMsg '-> Failed to intall Winget MSIXBundle for App Installer...' -LogColor 'red'
      }

      # Remove WinGet MSIXBundle
      Remove-Item -Path ('{0}\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -f $WAUConfig.InstallLocation) -Force -Confirm:$False -ErrorAction Continue
   }

   # Reset Winget Sources
   $ResolveWingetPath = Resolve-Path -Path "$env:programfiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" | Sort-Object -Property {
      [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
   }

   if ($ResolveWingetPath) 
   {
      # If multiple version, pick last one
      $WingetPath = $ResolveWingetPath[-1].Path
      & $WingetPath source reset --force

      # log
      Write-ToLog -LogMsg '-> Winget sources reseted.' -LogColor 'green'
   }

   # Create WAU Regkey if not present
   $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate'

   if (!(Test-Path -Path $regPath -ErrorAction SilentlyContinue)) 
   {
      $null = (New-Item -Path $regPath -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name DisplayName -Value 'Winget-AutoUpdate (WAU)' -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name DisplayIcon -Value 'C:\Windows\System32\shell32.dll,-16739' -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name NoModify -Value 1 -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name NoRepair -Value 1 -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name Publisher -Value 'Romanitho' -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name URLInfoAbout -Value 'https://github.com/Romanitho/Winget-AutoUpdate' -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name InstallLocation -Value $WorkingDir -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name UninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name QuietUninstallString -Value "powershell.exe -noprofile -executionpolicy bypass -file `"$WorkingDir\WAU-Uninstall.ps1`"" -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name WAU_UpdatePrerelease -Value 0 -PropertyType DWord -Force -Confirm:$False -ErrorAction SilentlyContinue)

      #log
      Write-ToLog -LogMsg ('-> {0} created.' -f $regPath) -LogColor 'green'
   }

   # Fix Notif where WAU_NotificationLevel is not set
   $regNotif = Get-ItemProperty -Path $regPath -Name WAU_NotificationLevel -ErrorAction SilentlyContinue

   if (!$regNotif) 
   {
      New-ItemProperty -Path $regPath -Name WAU_NotificationLevel -Value Full -Force

      # log
      Write-ToLog -LogMsg "-> Notification level setting was missing. Fixed with 'Full' option."
   }

   # Set WAU_MaxLogFiles/WAU_MaxLogSize if not set
   $MaxLogFiles = Get-ItemProperty -Path $regPath -Name WAU_MaxLogFiles -ErrorAction SilentlyContinue

   if (!$MaxLogFiles) 
   {
      $null = (New-ItemProperty -Path $regPath -Name WAU_MaxLogFiles -Value 3 -PropertyType DWord -Force -Confirm:$False -ErrorAction SilentlyContinue)
      $null = (New-ItemProperty -Path $regPath -Name WAU_MaxLogSize -Value 1048576 -PropertyType DWord -Force -Confirm:$False -ErrorAction SilentlyContinue)

      # log
      Write-ToLog -LogMsg '-> MaxLogFiles/MaxLogSize setting was missing. Fixed with 3/1048576 (in bytes, default is 1048576 = 1 MB).'
   }

   # Set WAU_ListPath if not set
   $ListPath = Get-ItemProperty -Path $regPath -Name WAU_ListPath -ErrorAction SilentlyContinue

   if (!$ListPath) 
   {
      $null = (New-ItemProperty -Path $regPath -Name WAU_ListPath -Force -Confirm:$False -ErrorAction SilentlyContinue)

      # log
      Write-ToLog -LogMsg '-> ListPath setting was missing. Fixed with empty string.'
   }

   # Set WAU_ModsPath if not set
   $ModsPath = (Get-ItemProperty -Path $regPath -Name WAU_ModsPath -ErrorAction SilentlyContinue)

   if (!$ModsPath) 
   {
      $null = (New-ItemProperty -Path $regPath -Name WAU_ModsPath -Force -Confirm:$False -ErrorAction SilentlyContinue)

      # log
      Write-ToLog -LogMsg '-> ModsPath setting was missing. Fixed with empty string.'
   }

   # Security check
   Write-ToLog -LogMsg '-> Checking Mods Directory:' -LogColor 'yellow'
   $Protected = Invoke-ModsProtect ('{0}\mods' -f $WAUConfig.InstallLocation)

   if ($Protected -eq $True) 
   {
      Write-ToLog -LogMsg '-> The mods directory is now secured!' -LogColor 'green'
   }
   elseif ($Protected -eq $False) 
   {
      Write-ToLog -LogMsg '-> The mods directory was already secured!' -LogColor 'green'
   }
   else 
   {
      Write-ToLog -LogMsg "-> Error: The mods directory couldn't be verified as secured!" -LogColor 'red'
   }

   # Convert about.xml if exists (old WAU versions) to reg
   $WAUAboutPath = ('{0}\config\about.xml' -f $WorkingDir)

   if (Test-Path -Path $WAUAboutPath -ErrorAction SilentlyContinue) 
   {
      [xml]$About = Get-Content -Path $WAUAboutPath -Encoding UTF8 -ErrorAction SilentlyContinue
      $null = (New-ItemProperty -Path $regPath -Name DisplayVersion -Value $About.app.version -Force -Confirm:$False -ErrorAction SilentlyContinue)

      # Remove file once converted
      $null = (Remove-Item -Path $WAUAboutPath -Force -Confirm:$False)

      #log
      Write-ToLog -LogMsg ('-> {0} converted.' -f $WAUAboutPath) -LogColor 'green'
   }

   # Convert config.xml if exists (previous WAU versions) to reg
   $WAUConfigPath = ('{0}\config\config.xml' -f $WorkingDir)

   if (Test-Path -Path $WAUConfigPath -ErrorAction SilentlyContinue) 
   {
      [xml]$Config = (Get-Content -Path $WAUConfigPath -Encoding UTF8 -ErrorAction SilentlyContinue)

      if ($Config.app.WAUautoupdate -eq 'False') 
      {
         $null = (New-ItemProperty -Path $regPath -Name WAU_DisableAutoUpdate -Value 1 -Force -Confirm:$False -ErrorAction SilentlyContinue)
      }

      if ($Config.app.NotificationLevel) 
      {
         $null = (New-ItemProperty -Path $regPath -Name WAU_NotificationLevel -Value $Config.app.NotificationLevel -Force -Confirm:$False -ErrorAction SilentlyContinue)
      }

      if ($Config.app.UseWAUWhiteList -eq 'True') 
      {
         $null = (New-ItemProperty -Path $regPath -Name WAU_UseWhiteList -Value 1 -PropertyType DWord -Force -Confirm:$False -ErrorAction SilentlyContinue)
      }

      if ($Config.app.WAUprerelease -eq 'True') 
      {
         $null = (New-ItemProperty -Path $regPath -Name WAU_UpdatePrerelease -Value 1 -PropertyType DWord -Force -Confirm:$False -ErrorAction SilentlyContinue)
      }

      # Remove file once converted
      $null = (Remove-Item -Path $WAUConfigPath -Force -Confirm:$False)

      # log
      Write-ToLog -LogMsg ('-> {0} converted.' -f $WAUConfigPath) -LogColor 'green'
   }

   # Remove old functions / files
   $FileNames = @(
      ('{0}\functions\Get-WAUConfig.ps1' -f $WorkingDir), 
      ('{0}\functions\Get-WAUCurrentVersion.ps1' -f $WorkingDir), 
      ('{0}\functions\Get-WAUUpdateStatus.ps1' -f $WorkingDir), 
      ('{0}\functions\Write-Log.ps1' -f $WorkingDir), 
      ('{0}\Version.txt' -f $WorkingDir)
   )

   foreach ($FileName in $FileNames) 
   {
      if (Test-Path -Path $FileName -ErrorAction SilentlyContinue) 
      {
         $null = (Remove-Item -Path $FileName -Force -Confirm:$False -ErrorAction SilentlyContinue)

         # log
         Write-ToLog -LogMsg ('-> {0} removed.' -f $FileName) -LogColor 'green'
      }
   }

   # Remove old registry key
   $RegistryKeys = @(
      'VersionMajor', 
      'VersionMinor'
   )

   foreach ($RegistryKey in $RegistryKeys) 
   {
      if (Get-ItemProperty -Path $regPath -Name $RegistryKey -ErrorAction SilentlyContinue) 
      {
         $null = (Remove-ItemProperty -Path $regPath -Name $RegistryKey -Force -Confirm:$False -ErrorAction SilentlyContinue)
      }
   }

   # Reset WAU_UpdatePostActions Value
   $null = ($WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 0 -Force -Confirm:$False -ErrorAction SilentlyContinue)

   # Get updated WAU Config
   $Script:WAUConfig = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate')

   # log
   Write-ToLog -LogMsg 'Post Update actions finished' -LogColor 'green'
}
