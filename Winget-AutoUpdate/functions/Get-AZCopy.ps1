# Function to get AZCopy, if it doesn't exist and update it, if it does

function Get-AZCopy
{
   [CmdletBinding()]
   param
   (
      [string]
      $WingetUpdatePath
   )

   $AZCopyLink = (Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue).headers.location
   $AZCopyVersionRegex = [regex]::new('(\d+\.\d+\.\d+)')
   $AZCopyLatestVersion = $AZCopyVersionRegex.Match($AZCopyLink).Value

   if ($null -eq $AZCopyLatestVersion -or '' -eq $AZCopyLatestVersion)
   {
      $AZCopyLatestVersion = '0.0.0'
   }

   if (Test-Path -Path ('{0}\azcopy.exe' -f $WingetUpdatePath) -PathType Leaf -ErrorAction SilentlyContinue)
   {
      $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
      $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value
      Write-ToLog -LogMsg ('AZCopy version {0} found' -f $AZCopyCurrentVersion)
   }
   else
   {
      Write-ToLog -LogMsg 'AZCopy not already installed'
      $AZCopyCurrentVersion = '0.0.0'
   }

   if (([version]$AZCopyCurrentVersion) -lt ([version]$AZCopyLatestVersion))
   {
      Write-ToLog -LogMsg ('Installing version {0} of AZCopy' -f $AZCopyLatestVersion)
      $null = (Invoke-WebRequest -Uri $AZCopyLink -UseBasicParsing -OutFile ('{0}\azcopyv10.zip' -f $WingetUpdatePath))
      Write-ToLog -LogMsg 'Extracting AZCopy zip file'
      $null = (Expand-Archive -Path ('{0}\azcopyv10.zip' -f $WingetUpdatePath) -DestinationPath $WingetUpdatePath -Force -Confirm:$false)
      $AZCopyPathSearch = (Resolve-Path -Path ('{0}\azcopy_*' -f $WingetUpdatePath))

      if ($AZCopyPathSearch -is [array])
      {
         $AZCopyEXEPath = $AZCopyPathSearch[$AZCopyPathSearch.Length - 1]
      }
      else
      {
         $AZCopyEXEPath = $AZCopyPathSearch
      }

      Write-ToLog -LogMsg "Copying 'azcopy.exe' to main folder"
      $null = (Copy-Item -Path ('{0}\azcopy.exe' -f $AZCopyEXEPath) -Destination ('{0}\' -f $WingetUpdatePath) -Force -Confirm:$false)
      Write-ToLog -LogMsg 'Removing temporary AZCopy files'
      $null = (Remove-Item -Path $AZCopyEXEPath -Recurse -Force -Confirm:$false)
      $null = (Remove-Item -Path ('{0}\azcopyv10.zip' -f $WingetUpdatePath) -Force -Confirm:$false)
      $AZCopyCurrentVersion = & "$WingetUpdatePath\azcopy.exe" -v
      $AZCopyCurrentVersion = $AZCopyVersionRegex.Match($AZCopyCurrentVersion).Value
      Write-ToLog -LogMsg ('AZCopy version {0} installed' -f $AZCopyCurrentVersion)
   }
}
