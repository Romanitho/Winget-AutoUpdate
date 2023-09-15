# Function to check if modification exists within 'mods' directory

function Test-Mods 
{
   # Takes care of a null situation
   [CmdletBinding()]
   param
   (
      [string]$app
   )

   $ModsPreInstall = $null
   $ModsOverride = $null
   $ModsUpgrade = $null
   $ModsInstall = $null
   $ModsInstalled = $null
   $Mods = ('{0}\mods' -f $WorkingDir)
    
   if (Test-Path -Path ('{0}\{1}-*' -f $Mods, $app) -ErrorAction SilentlyContinue) 
   {
      if (Test-Path -Path ('{0}\{1}-preinstall.ps1' -f $Mods, $app) -ErrorAction SilentlyContinue) 
      {
         $ModsPreInstall = ('{0}\{1}-preinstall.ps1' -f $Mods, $app)
      }
        
      if (Test-Path -Path ('{0}\{1}-override.txt' -f $Mods, $app) -ErrorAction SilentlyContinue) 
      {
         $ModsOverride = Get-Content -Path ('{0}\{1}-override.txt' -f $Mods, $app) -Raw
      }
        
      if (Test-Path -Path ('{0}\{1}-install.ps1' -f $Mods, $app) -ErrorAction SilentlyContinue) 
      {
         $ModsInstall = ('{0}\{1}-install.ps1' -f $Mods, $app)
         $ModsUpgrade = ('{0}\{1}-install.ps1' -f $Mods, $app)
      }
        
      if (Test-Path -Path ('{0}\{1}-upgrade.ps1' -f $Mods, $app) -ErrorAction SilentlyContinue) 
      {
         $ModsUpgrade = ('{0}\{1}-upgrade.ps1' -f $Mods, $app)
      }
        
      if (Test-Path -Path ('{0}\{1}-installed.ps1' -f $Mods, $app) -ErrorAction SilentlyContinue) 
      {
         $ModsInstalled = ('{0}\{1}-installed.ps1' -f $Mods, $app)
      }
   }

   return $ModsPreInstall, $ModsOverride, $ModsUpgrade, $ModsInstall, $ModsInstalled
}
