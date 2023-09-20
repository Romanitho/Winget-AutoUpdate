function Confirm-Installation
{
   # Set json export file

   [CmdletBinding()]
   param
   (
      [string]
      $AppName,
      [string]
      $AppVer
   )

   $JsonFile = ('{0}\Config\InstalledApps.json' -f $WorkingDir)

   # Get installed apps and version in json file
   $null = (& $Winget export -s winget -o $JsonFile --include-versions)

   # Get json content
   $Json = (Get-Content -Path $JsonFile -Raw | ConvertFrom-Json)

   # Get apps and version in hashtable
   $Packages = $Json.Sources.Packages

   # Remove json file
   $null = (Remove-Item -Path $JsonFile -Force -Confirm:$false -ErrorAction SilentlyContinue)

   # Search for specific app and version
   $Apps = $Packages | Where-Object -FilterScript {
      ($_.PackageIdentifier -eq $AppName -and $_.Version -like ('{0}*' -f $AppVer))
   }

   if ($Apps)
   {
      return $true
   }
   else
   {
      return $false
   }
}
