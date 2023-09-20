# Function to get the allow List apps

function Get-IncludedApps
{
   if ($GPOList)
   {
      if (Test-Path -Path 'HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList' -ErrorAction SilentlyContinue)
      {
         $Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList\'
         $ValueNames = (Get-Item -Path 'HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList').Property

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
   elseif (Test-Path -Path ('{0}\included_apps.txt' -f $WorkingDir) -ErrorAction SilentlyContinue)
   {
      return (Get-Content -Path ('{0}\included_apps.txt' -f $WorkingDir)).Trim() | Where-Object -FilterScript {
         $_.length -gt 0
      }
   }
}
