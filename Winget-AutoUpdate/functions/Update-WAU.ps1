# Function to update WAU

function Update-WAU
{
   $OnClickAction = 'https://github.com/Romanitho/Winget-AutoUpdate/releases'
   $Button1Text = $NotifLocale.local.outputs.output[10].message
   
   #Send available update notification
   $Title = $NotifLocale.local.outputs.output[2].title -f 'Winget-AutoUpdate'
   $Message = $NotifLocale.local.outputs.output[2].message -f $WAUCurrentVersion, $WAUAvailableVersion
   $MessageType = 'info'
   Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
   
   # Run WAU update
   try
   {
      # Force to create a zip file
      $ZipFile = ('{0}\WAU_update.zip' -f $WorkingDir)
      $null = New-Item -Path $ZipFile -ItemType File -Force
      
      # Download the zip
      Write-ToLog -LogMsg ('Downloading the GitHub Repository version {0}' -f $WAUAvailableVersion) -LogColor 'Cyan'
      $null = (Invoke-RestMethod -Uri ('https://github.com/Romanitho/Winget-AutoUpdate/releases/download/v{0}/WAU.zip' -f ($WAUAvailableVersion)) -OutFile $ZipFile)
      
      # Extract Zip File
      Write-ToLog -LogMsg 'Unzipping the WAU Update package' -LogColor 'Cyan'
      $location = ('{0}\WAU_update' -f $WorkingDir)
      $null = (Expand-Archive -Path $ZipFile -DestinationPath $location -Force)
      $null = (Get-ChildItem -Path $location -Recurse | Unblock-File -ErrorAction SilentlyContinue)
      
      # Update scritps
      Write-ToLog -LogMsg 'Updating WAU...' -LogColor 'Yellow'
      $TempPath = (Resolve-Path -Path ('{0}\Winget-AutoUpdate\' -f $location) -ErrorAction SilentlyContinue)[0].Path
      if ($TempPath)
      {
         $null = (Copy-Item -Path ('{0}\*' -f $TempPath) -Destination ('{0}\' -f $WorkingDir) -Exclude 'icons' -Recurse -Force -Confirm:$false)
      }
      
      # Remove update zip file and update temp folder
      Write-ToLog -LogMsg 'Done. Cleaning temp files...' -LogColor 'Cyan'
      $null = (Remove-Item -Path $ZipFile -Force -Confirm:$false -ErrorAction SilentlyContinue)
      $null = (Remove-Item -Path $location -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue)
      
      # Set new version to registry
      $WAUConfig | New-ItemProperty -Name DisplayVersion -Value $WAUAvailableVersion -Force
      $WAUConfig | New-ItemProperty -Name VersionMajor -Value ([version]$WAUAvailableVersion.Replace('-', '.')).Major -Force
      $WAUConfig | New-ItemProperty -Name VersionMinor -Value ([version]$WAUAvailableVersion.Replace('-', '.')).Minor -Force
      
      # Set Post Update actions to 1
      $WAUConfig | New-ItemProperty -Name WAU_PostUpdateActions -Value 1 -Force
      
      # Send success Notif
      Write-ToLog -LogMsg 'WAU Update completed.' -LogColor 'Green'
      $Title = $NotifLocale.local.outputs.output[3].title -f 'Winget-AutoUpdate'
      $Message = $NotifLocale.local.outputs.output[3].message -f $WAUAvailableVersion
      $MessageType = 'success'
      Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
      
      # Rerun with newer version
      Write-ToLog -LogMsg 'Re-run WAU'
      Start-Process -FilePath powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$WorkingDir\winget-upgrade.ps1`""
      
      exit
   }
   catch
   {
      # Send Error Notif
      $Title = $NotifLocale.local.outputs.output[4].title -f 'Winget-AutoUpdate'
      $Message = $NotifLocale.local.outputs.output[4].message
      $MessageType = 'error'
      Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Button1Action $OnClickAction -Button1Text $Button1Text
      Write-ToLog -LogMsg 'WAU Update failed' -LogColor 'Red'
   }
}
