#Function to get the Block List apps

function Get-ExcludedApps 
{
   if ($GPOList) 
   {
      if (Test-Path -Path 'HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList' -ErrorAction SilentlyContinue) 
      {
         $Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList\'

         $ValueNames = (Get-Item -Path 'HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList').Property

         foreach ($ValueName in $ValueNames) 
         {
            $AppIDs = [Microsoft.Win32.Registry]::GetValue($Key, $ValueName, $false)
            [PSCustomObject]@{
               Value = $ValueName
               Data  = $AppIDs.Trim()
            }
         }
      }

      return $AppIDs
   }
   elseif (Test-Path -Path ('{0}\excluded_apps.txt' -f $WorkingDir) -ErrorAction SilentlyContinue) 
   {
      return (Get-Content -Path ('{0}\excluded_apps.txt' -f $WorkingDir)).Trim() | Where-Object -FilterScript {
         $_.length -gt 0 
      }
   }
}
