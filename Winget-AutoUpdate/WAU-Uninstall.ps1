<#
      .SYNOPSIS
      Uninstall Winget-AutoUpdate

      .DESCRIPTION
      Uninstalls Winget-AutoUpdate (DEFAULT: clean old install)
      https://github.com/Romanitho/Winget-AutoUpdate

      .PARAMETER NoClean
      Uninstall Winget-AutoUpdate (keep critical files)

      .EXAMPLE
      .\WAU-Uninstall.ps1 -NoClean

#>
[CmdletBinding()]
param(
   [Switch] $NoClean = $false
)

Write-Host -Object "`n"
Write-Host -Object "`t        888       888        d8888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888   o   888       d88888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888  d8b  888      d88P888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888 d888b 888     d88P 888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888d88888b888    d88P  888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        88888P Y88888   d88P   888  888     888" -ForegroundColor Cyan
Write-Host -Object "`t        8888P   Y8888  d88P    888  888     888" -ForegroundColor Magenta
Write-Host -Object "`t        888P     Y888 d88P     888   Y8888888P`n" -ForegroundColor Magenta
Write-Host -Object "`t                    Winget-AutoUpdate`n" -ForegroundColor Cyan
Write-Host -Object "`t     https://github.com/Romanitho/Winget-AutoUpdate`n" -ForegroundColor Magenta
Write-Host -Object "`t________________________________________________________`n`n"

try 
{
   Write-Host -Object 'Uninstalling WAU...' -ForegroundColor Yellow

   # Get registry install location
   $InstallLocation = (Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\' -Name InstallLocation)

   # Check if installed location exists and delete
   if (Test-Path -Path ($InstallLocation)) 
   {
      if (!$NoClean) 
      {
         $null = (Remove-Item -Path ('{0}\*' -f $InstallLocation) -Force -Confirm:$false -Recurse -Exclude '*.log')
      }
      else 
      {
         # Keep critical files
         $null = (Get-ChildItem -Path $InstallLocation -Exclude *.txt, mods, logs | Remove-Item -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue)
      }
      $null = (Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false)
      $null = (Get-ScheduledTask -TaskName 'Winget-AutoUpdate-Notify' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false)
      $null = (Get-ScheduledTask -TaskName 'Winget-AutoUpdate-UserContext' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false)
      $null = & "$env:windir\system32\reg.exe" delete 'HKCR\AppUserModelId\Windows.SystemToast.Winget.Notification' /f
      $null = & "$env:windir\system32\reg.exe" delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate' /f
        
      if (Test-Path -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate' -ErrorAction SilentlyContinue) 
      {
         $null = & "$env:windir\system32\reg.exe" delete 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate' /f
      }

      if ((Test-Path -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)")) 
      {
         $null = (Remove-Item -Path "${env:ProgramData}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate (WAU)" -Recurse -Force -Confirm:$false)
      }

      if ((Test-Path -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk")) 
      {
         $null = (Remove-Item -Path "${env:Public}\Desktop\WAU - Check for updated Apps.lnk" -Force -Confirm:$false)
      }

      # Remove Intune Logs if they are existing
      if (Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log") 
      {
         $null = (Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -Force -Confirm:$false -ErrorAction SilentlyContinue)
      }
      if (Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ErrorAction SilentlyContinue) 
      {
         $null = (Remove-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -Force -Confirm:$false -ErrorAction SilentlyContinue)
      }

      Write-Host -Object 'Uninstallation succeeded!' -ForegroundColor Green
   }
   else 
   {
      Write-Host -Object ('{0} not found! Uninstallation failed!' -f $InstallLocation) -ForegroundColor Red
   }
}
catch 
{
   Write-Host -Object "`nUninstallation failed! Run as admin ?" -ForegroundColor Red
}

Start-Sleep -Seconds 2
