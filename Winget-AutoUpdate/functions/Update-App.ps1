# Function to update an App

Function Update-App 
{
   # Get App Info
   [CmdletBinding()]
   param
   (
      $app
   )
   $ReleaseNoteURL = Get-AppInfo $app.Id
   if ($ReleaseNoteURL) 
   {
      $Button1Text = $NotifLocale.local.outputs.output[10].message
   }

   # Send available update notification
   Write-ToLog -LogMsg ('Updating {0} from {1} to {2}...' -f $app.Name, $app.Version, $app.AvailableVersion) -LogColor 'Cyan'
   $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
   $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
   $MessageType = 'info'
   $Balise = $($app.Name)
   Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text

   # Check if mods exist for preinstall/install/upgrade
   $ModsPreInstall, $ModsOverride, $ModsUpgrade, $ModsInstall, $ModsInstalled = Test-Mods $($app.Id)

   # Winget upgrade
   Write-ToLog -LogMsg ("##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '{0}'   ##########" -f $app.Id) -LogColor 'Gray'

   # If PreInstall script exist
   if ($ModsPreInstall) 
   {
      Write-ToLog -LogMsg ('Modifications for {0} before upgrade are being applied...' -f $app.Id) -LogColor 'Yellow'
      & "$ModsPreInstall"
   }

   # Run Winget Upgrade command
   if ($ModsOverride) 
   {
      Write-ToLog -LogMsg ('-> Running (overriding default): Winget upgrade --id {0} --accept-package-agreements --accept-source-agreements --override {1}' -f $app.Id, $ModsOverride)
      & $Winget upgrade --id $($app.Id) --accept-package-agreements --accept-source-agreements --override $ModsOverride | Tee-Object -FilePath $LogFile -Append
   }
   else 
   {
      Write-ToLog -LogMsg ('-> Running: Winget upgrade --id {0} --accept-package-agreements --accept-source-agreements -h' -f $app.Id)
      & $Winget upgrade --id $($app.Id) --accept-package-agreements --accept-source-agreements -h | Tee-Object -FilePath $LogFile -Append
   }

   if ($ModsUpgrade) 
   {
      Write-ToLog -LogMsg ('Modifications for {0} during upgrade are being applied...' -f $app.Id) -LogColor 'Yellow'
      & "$ModsUpgrade"
   }

   # Check if application updated properly
   $FailedToUpgrade = $false
   $ConfirmInstall = Confirm-Installation $($app.Id) $($app.AvailableVersion)

   if ($ConfirmInstall -ne $true) 
   {
      # Upgrade failed!
      # Test for a Pending Reboot (Component Based Servicing/WindowsUpdate/CCM_ClientUtilities)
      $PendingReboot = Test-PendingReboot
      if ($PendingReboot -eq $true) 
      {
         Write-ToLog -LogMsg ("-> A Pending Reboot lingers and probably prohibited {0} from upgrading...`n-> ...an install for {1} is NOT executed!" -f $app.Name) -LogColor 'Red'
         $FailedToUpgrade = $true
         break
      }

      # If app failed to upgrade, run Install command
      Write-ToLog -LogMsg ('-> An upgrade for {0} failed, now trying an install instead...' -f $app.Name) -LogColor 'Yellow'

      if ($ModsOverride) 
      {
         Write-ToLog -LogMsg ('-> Running (overriding default): Winget install --id {0} --accept-package-agreements --accept-source-agreements --force --override {1}' -f $app.Id, $ModsOverride)
         & $Winget install --id $($app.Id) --accept-package-agreements --accept-source-agreements --force --override $ModsOverride | Tee-Object -FilePath $LogFile -Append
      }
      else 
      {
         Write-ToLog -LogMsg ('-> Running: Winget install --id {0} --accept-package-agreements --accept-source-agreements --force -h' -f $app.Id)
         & $Winget install --id $($app.Id) --accept-package-agreements --accept-source-agreements --force -h | Tee-Object -FilePath $LogFile -Append
      }

      if ($ModsInstall) 
      {
         Write-ToLog -LogMsg ('Modifications for {0} during install are being applied...' -f $app.Id) -LogColor 'Yellow'
         & "$ModsInstall"
      }

      # Check if application installed properly
      $ConfirmInstall = Confirm-Installation $($app.Id) $($app.AvailableVersion)
      if ($ConfirmInstall -eq $false) 
      {
         $FailedToUpgrade = $true
      }
   }

   if ($FailedToUpgrade -eq $false) 
   {
      if ($ModsInstalled) 
      {
         Write-ToLog -LogMsg ('Modifications for {0} after upgrade/install are being applied...' -f $app.Id) -LogColor 'Yellow'
         & "$ModsInstalled"
      }
   }

   Write-ToLog -LogMsg ("##########   WINGET UPGRADE PROCESS FINISHED FOR APPLICATION ID '{0}'   ##########" -f $app.Id) -LogColor 'Gray'

   # Notify installation
   if ($FailedToUpgrade -eq $false) 
   {
      # Send success updated app notification
      Write-ToLog -LogMsg ('{0} updated to {1} !' -f $app.Name, $app.AvailableVersion) -LogColor 'Green'

      # Send Notif
      $Title = $NotifLocale.local.outputs.output[3].title -f $($app.Name)
      $Message = $NotifLocale.local.outputs.output[3].message -f $($app.AvailableVersion)
      $MessageType = 'success'
      $Balise = $($app.Name)
      Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
      $Script:InstallOK += 1
   }
   else 
   {
      # Send failed updated app notification
      Write-ToLog -LogMsg ('{0} update failed.' -f $app.Name) -LogColor 'Red'

      # Send Notif
      $Title = $NotifLocale.local.outputs.output[4].title -f $($app.Name)
      $Message = $NotifLocale.local.outputs.output[4].message
      $MessageType = 'error'
      $Balise = $($app.Name)
      Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise -Button1Action $ReleaseNoteURL -Button1Text $Button1Text
   }
}
