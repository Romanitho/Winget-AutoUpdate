# Function to check Block/Allow List External Path

function Test-ListPath 
{
   # URL, UNC or Local Path 
   [CmdletBinding()]
   param
   (
      [string]$ListPath,
      [string]$UseWhiteList,
      [string]$WingetUpdatePath
   )
   
   if ($UseWhiteList) 
   {
      $ListType = 'included_apps.txt'
   }
   else 
   {
      $ListType = 'excluded_apps.txt'
   }

   # Get local and external list paths
   $LocalList = -join ($WingetUpdatePath, '\', $ListType)
   $ExternalList = -join ($ListPath, '\', $ListType)

   # Check if a list exists
   if (Test-Path -Path $LocalList -ErrorAction SilentlyContinue) 
   {
      $dateLocal = (Get-Item -Path $LocalList).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
   }

   # If path is URL
   if ($ListPath -like 'http*') 
   {
      $ExternalList = -join ($ListPath, '/', $ListType)
      $wc = (New-Object -TypeName System.Net.WebClient)

      try 
      {
         $null = $wc.OpenRead($ExternalList).Close()
         $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString('yyyy-MM-dd HH:mm:ss')
            
         if ($dateExternal -gt $dateLocal) 
         {
            try 
            {
               $wc.DownloadFile($ExternalList, $LocalList)
            }
            catch 
            {
               $Script:ReachNoPath = $True
               return $False
            }
            return $True
         }
      }
      catch 
      {
         try 
         {
            $content = $wc.DownloadString(('{0}' -f $ExternalList))

            if ($null -ne $content -and $content -match '\w\.\w') 
            {
               $wc.DownloadFile($ExternalList, $LocalList)
               return $True
            }
            else 
            {
               $Script:ReachNoPath = $True
               return $False
            }
         }
         catch 
         {
            $Script:ReachNoPath = $True
            return $False
         }
      }
   }
   else 
   {
      # If path is UNC or local
      if (Test-Path -Path $ExternalList) 
      {
         try 
         {
            $dateExternal = (Get-Item -Path ('{0}' -f $ExternalList)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
         }
         catch 
         {
            $Script:ReachNoPath = $True
            return $False
         }

         if ($dateExternal -gt $dateLocal) 
         {
            try 
            {
               Copy-Item -Path $ExternalList -Destination $LocalList -Force
            }
            catch 
            {
               $Script:ReachNoPath = $True
               return $False
            }
            return $True
         }
      }
      else 
      {
         $Script:ReachNoPath = $True
      }

      return $False
   }
}
