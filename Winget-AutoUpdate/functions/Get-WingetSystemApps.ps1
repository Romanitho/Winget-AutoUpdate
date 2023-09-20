function Get-WingetSystemApps
{
   # Json File, where to export system installed apps
   $jsonFile = ('{0}\winget_system_apps.txt' -f $WorkingDir)

   # Get list of installed Winget apps to json file
   $null = (& $Winget export -o $jsonFile --accept-source-agreements -s winget)

   # Convert json file to txt file with app ids
   $InstalledApps = (Get-Content -Path $jsonFile | ConvertFrom-Json)

   # Save app list
   $null = (Set-Content -Value $InstalledApps.Sources.Packages.PackageIdentifier -Path $jsonFile -Force -Confirm:$False -ErrorAction SilentlyContinue)

   # Sort app list
   $null = (Get-Content -Path $jsonFile | Sort-Object | Set-Content -Path $jsonFile -Force -Confirm:$False -ErrorAction SilentlyContinue)
}
