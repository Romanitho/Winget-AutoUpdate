# Initialisation

function Start-Init
{
   # Config console output encoding
   [Console]::OutputEncoding = [Text.Encoding]::UTF8
   
   # Workaround for ARM64 (Access Denied / Win32 internal Server error)
   $Script:ProgressPreference = 'SilentlyContinue'
   $caller = ((Get-ChildItem -Path $MyInvocation.PSCommandPath).Name)
   
   if ($caller -eq 'Winget-Upgrade.ps1')
   {
      # Log Header
      $Log = "`n##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern)`n##################################################"
      $Log | Write-Host
      # Logs initialisation
      $Script:LogFile = ('{0}\logs\updates.log' -f $WorkingDir)
   }
   elseif ($caller -eq 'Winget-AutoUpdate-Install.ps1')
   {
      $Script:LogFile = ('{0}\logs\updates.log' -f $WingetUpdatePath)
   }
   
   if (!(Test-Path -Path $LogFile -ErrorAction SilentlyContinue))
   {
      # Create file if doesn't exist
      $null = (New-Item -ItemType File -Path $LogFile -Force -Confirm:$false)
      # Set ACL for users on logfile
      $NewAcl = (Get-Acl -Path $LogFile)
      $identity = (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList S-1-5-11)
      $fileSystemRights = 'Modify'
      $type = 'Allow'
      $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
      $fileSystemAccessRule = (New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList)
      $NewAcl.SetAccessRule($fileSystemAccessRule)
      Set-Acl -Path $LogFile -AclObject $NewAcl
   }
   elseif ((Test-Path -Path $LogFile -ErrorAction SilentlyContinue) -and ($caller -eq 'Winget-AutoUpdate-Install.ps1'))
   {
      #Set ACL for users on logfile
      $NewAcl = (Get-Acl -Path $LogFile)
      $identity = (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList S-1-5-11)
      $fileSystemRights = 'Modify'
      $type = 'Allow'
      $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
      $fileSystemAccessRule = (New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList)
      $NewAcl.SetAccessRule($fileSystemAccessRule)
      $null = (Set-Acl -Path $LogFile -AclObject $NewAcl)
   }
   
   # Check if Intune Management Extension Logs folder and WAU-updates.log exists, make symlink
   if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs") -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log"))
   {
      Write-Host -Object "`nCreating SymLink for log file (WAU-updates) in Intune Management Extension log folder" -ForegroundColor Yellow
      $null = New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-updates.log" -ItemType SymbolicLink -Value $LogFile -Force -ErrorAction SilentlyContinue
   }
   
   # Check if Intune Management Extension Logs folder and WAU-install.log exists, make symlink
   if ((Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs" -ErrorAction SilentlyContinue) -and (Test-Path -Path ('{0}\logs\install.log' -f $WorkingDir) -ErrorAction SilentlyContinue) -and !(Test-Path -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ErrorAction SilentlyContinue))
   {
      Write-Host -Object "`nCreating SymLink for log file (WAU-install) in Intune Management Extension log folder" -ForegroundColor Yellow
      $null = (New-Item -Path "${env:ProgramData}\Microsoft\IntuneManagementExtension\Logs\WAU-install.log" -ItemType SymbolicLink -Value ('{0}\logs\install.log' -f $WorkingDir) -Force -ErrorAction SilentlyContinue)
   }
   
   if ($caller -eq 'Winget-Upgrade.ps1')
   {
      # Log file
      $Log | Out-File -FilePath $LogFile -Append -Force
   }
}
