# Function to get the winget command regarding execution context (User, System...)

function Get-WingetCmd
{

   # Get WinGet Path (if Admin context)
   # Includes Workaround for ARM64 (removed X64 and replaces it with a wildcard)
   $ResolveWingetPath = (Resolve-Path -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe" | Sort-Object -Property {
         [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
      })

   if ($ResolveWingetPath)
   {
      # If multiple version, pick last one
      $WingetPath = $ResolveWingetPath[-1].Path
   }

   #If running under System or Admin context obtain Winget from Program Files
   if ((([Security.Principal.WindowsIdentity]::GetCurrent().User) -eq 'S-1-5-18') -or ($WingetPath))
   {
      if (Test-Path -Path ('{0}\winget.exe' -f $WingetPath) -ErrorAction SilentlyContinue)
      {
         $Script:Winget = ('{0}\winget.exe' -f $WingetPath)
      }
   }
   else
   {
      #Get Winget Location in User context
      $WingetCmd = (Get-Command -Name winget.exe -ErrorAction SilentlyContinue)

      if ($WingetCmd)
      {
         $Script:Winget = $WingetCmd.Source
      }
   }

   if (!($Script:Winget))
   {
      Write-ToLog 'Winget not installed or detected !' 'Red'

      return $false
   }

   # Run winget to list apps and accept source agrements (necessary on first run)
   $null = (& $Winget list --accept-source-agreements -s winget)

   # Log Winget installed version
   $WingetVer = & $Winget --version
   Write-ToLog ('Winget Version: {0}' -f $WingetVer)

   return $true

}
