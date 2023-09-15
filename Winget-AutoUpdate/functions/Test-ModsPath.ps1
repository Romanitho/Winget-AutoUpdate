#Function to check mods External Path

function Test-ModsPath
{
   # URL, UNC or Local Path
   # Get local and external Mods paths
   
   [CmdletBinding()]
   param
   (
      [string]
      $ModsPath,
      [string]
      $WingetUpdatePath,
      [string]
      $AzureBlobSASURL
   )
   $LocalMods = -join ($WingetUpdatePath, '\', 'mods')
   $ExternalMods = $ModsPath
   
   # Get File Names Locally
   $InternalModsNames = (Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1, *.txt -ErrorAction SilentlyContinue)
   $InternalBinsNames = (Get-ChildItem -Path $LocalMods"\bins" -Name -Recurse -Include *.exe -ErrorAction SilentlyContinue)
   
   # If path is URL
   if ($ExternalMods -like 'http*')
   {
      # enable TLS 1.2 and TLS 1.1 protocols
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11
      # Get Index of $ExternalMods (or index page with href listing of all the Mods)
      try
      {
         $WebResponse = (Invoke-WebRequest -Uri $ExternalMods -UseBasicParsing)
      }
      catch
      {
         $Script:ReachNoPath = $True
         
         return $False
      }
      
      # Check for bins, download if newer. Delete if not external
      $ExternalBins = ('{0}/bins' -f $ModsPath)
      
      if ($WebResponse -match 'bins/')
      {
         $BinResponse = Invoke-WebRequest -Uri $ExternalBins -UseBasicParsing
         # Collect the external list of href links
         $BinLinks = $BinResponse.Links | Select-Object -ExpandProperty HREF
         # If there's a directory path in the HREF:s, delete it (IIS)
         $CleanBinLinks = $BinLinks -replace '/.*/', ''
         # Modify strings to HREF:s
         $index = 0
         
         foreach ($Bin in $CleanBinLinks)
         {
            if ($Bin)
            {
               $CleanBinLinks[$index] = '<a href="' + $Bin + '"> ' + $Bin + '</a>'
            }
            $index++
         }
         
         # Delete Local Bins that don't exist Externally
         $index = 0
         $CleanLinks = $BinLinks -replace '/.*/', ''
         
         foreach ($Bin in $InternalBinsNames)
         {
            if ($CleanLinks -notcontains $Bin)
            {
               $null = (Remove-Item -Path $LocalMods\bins\$Bin -Force -Confirm:$False -ErrorAction SilentlyContinue)
            }
            
            $index++
         }
         
         $CleanBinLinks = $BinLinks -replace '/.*/', ''
         $Bin = ''
         # Loop through all links
         $wc = New-Object -TypeName System.Net.WebClient
         $CleanBinLinks | ForEach-Object -Process {
            # Check for .exe in listing/HREF:s in an index page pointing to .exe
            if ($_ -like '*.exe')
            {
               $dateExternalBin = ''
               $dateLocalBin = ''
               $null = $wc.OpenRead(('{0}/{1}' -f $ExternalBins, $_)).Close()
               $dateExternalBin = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString('yyyy-MM-dd HH:mm:ss')
               
               if (Test-Path -Path $LocalMods"\bins\"$_)
               {
                  $dateLocalBin = (Get-Item -Path ('{0}\bins\{1}' -f $LocalMods, $_)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
               }
               
               if ($dateExternalBin -gt $dateLocalBin)
               {
                  $SaveBin = Join-Path -Path ('{0}\bins' -f $LocalMods) -ChildPath $_
                  Invoke-WebRequest -Uri ('{0}/{1}' -f $ExternalBins, $_) -OutFile $SaveBin.Replace('%20', ' ') -UseBasicParsing
               }
            }
         }
      }
      
      # Collect the external list of href links
      $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty HREF
      # If there's a directory path in the HREF:s, delete it (IIS)
      $CleanLinks = $ModLinks -replace '/.*/', ''
      # Modify strings to HREF:s
      $index = 0
      
      foreach ($Mod in $CleanLinks)
      {
         if ($Mod)
         {
            $CleanLinks[$index] = '<a href="' + $Mod + '"> ' + $Mod + '</a>'
         }
         $index++
      }
      
      # Delete Local Mods that don't exist Externally
      $DeletedMods = 0
      $index = 0
      $CleanLinks = $ModLinks -replace '/.*/', ''
      
      foreach ($Mod in $InternalModsNames)
      {
         if ($CleanLinks -notcontains $Mod)
         {
            $null = (Remove-Item -Path $LocalMods\$Mod -Force -Confirm:$False -ErrorAction SilentlyContinue)
            $DeletedMods++
         }
         $index++
      }
      
      $CleanLinks = $ModLinks -replace '/.*/', ''
      
      # Loop through all links
      
      $CleanLinks | ForEach-Object -Process {
         # Check for .ps1/.txt in listing/HREF:s in an index page pointing to .ps1/.txt
         if (($_ -like '*.ps1') -or ($_ -like '*.txt'))
         {
            try
            {
               $dateExternalMod = ''
               $dateLocalMod = ''
               $null = $wc.OpenRead(('{0}/{1}' -f $ExternalMods, $_)).Close()
               $dateExternalMod = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString('yyyy-MM-dd HH:mm:ss')
               
               if (Test-Path -Path $LocalMods"\"$_)
               {
                  $dateLocalMod = (Get-Item -Path ('{0}\{1}' -f $LocalMods, $_)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
               }
               
               if ($dateExternalMod -gt $dateLocalMod)
               {
                  try
                  {
                     $SaveMod = Join-Path -Path ('{0}\' -f $LocalMods) -ChildPath $_
                     $Mod = '{0}/{1}' -f $ModsPath.TrimEnd('/'), $_
                     $null = (Invoke-WebRequest -Uri $Mod -OutFile $SaveMod -UseBasicParsing)
                     $ModsUpdated++
                  }
                  catch
                  {
                     $Script:ReachNoPath = $True
                  }
               }
            }
            catch
            {
               if (($_ -like '*.ps1') -or ($_ -like '*.txt'))
               {
                  $Script:ReachNoPath = $True
               }
            }
         }
      }
      return $ModsUpdated, $DeletedMods
   }
   # If Path is Azure Blob
   elseif ($ExternalMods -like 'AzureBlob')
   {
      Write-ToLog -LogMsg 'Azure Blob Storage set as mod source'
      Write-ToLog -LogMsg 'Checking AZCopy'
      Get-AZCopy $WingetUpdatePath
      
      # Safety check to make sure we really do have azcopy.exe and a Blob URL
      if ((Test-Path -Path ('{0}\azcopy.exe' -f $WingetUpdatePath) -PathType Leaf) -and ($null -ne $AzureBlobSASURL))
      {
         Write-ToLog -LogMsg 'Syncing Blob storage with local storage'
         
         $AZCopySyncOutput = & $WingetUpdatePath\azcopy.exe sync $AzureBlobSASURL $LocalMods --from-to BlobLocal --delete-destination=true
         $AZCopyOutputLines = $AZCopySyncOutput.Split([Environment]::NewLine)
         
         foreach ($_ in $AZCopyOutputLines)
         {
            $AZCopySyncAdditionsRegex = [regex]::new('(?<=Number of Copy Transfers Completed:\s+)\d+')
            $AZCopySyncDeletionsRegex = [regex]::new('(?<=Number of Deletions at Destination:\s+)\d+')
            $AZCopySyncErrorRegex = [regex]::new('^Cannot perform sync due to error:')
            
            $AZCopyAdditions = [int]$AZCopySyncAdditionsRegex.Match($_).Value
            $AZCopyDeletions = [int]$AZCopySyncDeletionsRegex.Match($_).Value
            
            if ($AZCopyAdditions -ne 0)
            {
               $ModsUpdated = $AZCopyAdditions
            }
            
            if ($AZCopyDeletions -ne 0)
            {
               $DeletedMods = $AZCopyDeletions
            }
            
            if ($AZCopySyncErrorRegex.Match($_).Value)
            {
               Write-ToLog -LogMsg ('AZCopy Sync Error! {0}' -f $_)
            }
         }
      }
      else
      {
         Write-ToLog -LogMsg "Error 'azcopy.exe' or SAS Token not found!"
      }
      
      return $ModsUpdated, $DeletedMods
   }
   else
   {
      # If path is UNC or local
      $ExternalBins = ('{0}\bins' -f $ModsPath)
      
      if (Test-Path -Path $ExternalBins"\*.exe")
      {
         $ExternalBinsNames = (Get-ChildItem -Path $ExternalBins -Name -Recurse -Include *.exe)
         
         # Delete Local Bins that don't exist Externally
         foreach ($Bin in $InternalBinsNames)
         {
            if ($Bin -notin $ExternalBinsNames)
            {
               $null = (Remove-Item -Path $LocalMods\bins\$Bin -Force -Confirm:$False -ErrorAction SilentlyContinue)
            }
         }
         
         # Copy newer external bins
         foreach ($Bin in $ExternalBinsNames)
         {
            $dateExternalBin = ''
            $dateLocalBin = ''
            
            if (Test-Path -Path $LocalMods"\bins\"$Bin)
            {
               $dateLocalBin = (Get-Item -Path ('{0}\bins\{1}' -f $LocalMods, $Bin)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            }
            
            $dateExternalBin = (Get-Item -Path ('{0}\{1}' -f $ExternalBins, $Bin)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            
            if ($dateExternalBin -gt $dateLocalBin)
            {
               $null = Copy-Item -Path $ExternalBins\$Bin -Destination $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue
            }
         }
      }
      
      if ((Test-Path -Path $ExternalMods"\*.ps1") -or (Test-Path -Path $ExternalMods"\*.txt"))
      {
         # Get File Names Externally
         $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1, *.txt
         
         # Delete Local Mods that don't exist Externally
         $DeletedMods = 0
         
         foreach ($Mod in $InternalModsNames)
         {
            if ($Mod -notin $ExternalModsNames)
            {
               $null = Remove-Item -Path $LocalMods\$Mod -Force -ErrorAction SilentlyContinue
               $DeletedMods++
            }
         }
         
         # Copy newer external mods
         foreach ($Mod in $ExternalModsNames)
         {
            $dateExternalMod = ''
            $dateLocalMod = ''
            if (Test-Path -Path $LocalMods"\"$Mod)
            {
               $dateLocalMod = (Get-Item -Path ('{0}\{1}' -f $LocalMods, $Mod)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            }
            
            $dateExternalMod = (Get-Item -Path ('{0}\{1}' -f $ExternalMods, $Mod)).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            
            if ($dateExternalMod -gt $dateLocalMod)
            {
               $null = Copy-Item -Path $ExternalMods\$Mod -Destination $LocalMods\$Mod -Force -ErrorAction SilentlyContinue
               $ModsUpdated++
            }
         }
      }
      else
      {
         $Script:ReachNoPath = $True
      }
      
      return $ModsUpdated, $DeletedMods
   }
}
