# Function to rotate the logs

function Invoke-LogRotation 
{
   <#
         .SYNOPSIS
         Handle log rotation.
         .DESCRIPTION
         Invoke-LogRotation handles log rotation
         .NOTES
         Author: Øyvind Kallstad (Minimized and changed for WAU 12.01.2023 by Göran Axel Johannesson)
         URL: https://www.powershellgallery.com/packages/Communary.Logger/1.1
         Date: 21.11.2014
         Version: 1.0
   #> 
   param
   (
      [string]$LogFile,
      [int]$MaxLogFiles,
      [int]$MaxLogSize
   )
   
   try 
   {
      # get current size of log file
      $currentSize = (Get-Item -Path $LogFile).Length

      # get log name
      $logFileName = (Split-Path -Path $LogFile -Leaf)
      $logFilePath = (Split-Path -Path $LogFile)
      $logFileNameWithoutExtension = [IO.Path]::GetFileNameWithoutExtension($logFileName)
      $logFileNameExtension = [IO.Path]::GetExtension($logFileName)

      # if MaxLogFiles is 1 just keep the original one and let it grow
      if (-not($MaxLogFiles -eq 1)) 
      {
         if ($currentSize -ge $MaxLogSize) 
         {
            # construct name of archived log file
            $newLogFileName = $logFileNameWithoutExtension + (Get-Date -Format 'yyyyMMddHHmmss').ToString() + $logFileNameExtension

            # copy old log file to new using the archived name constructed above
            $null = (Copy-Item -Path $LogFile -Destination (Join-Path -Path (Split-Path -Path $LogFile) -ChildPath $newLogFileName))

            # Create a new log file
            try 
            {
               $null = (Remove-Item -Path $LogFile -Force -Confirm:$False -ErrorAction SilentlyContinue)
               $null = (New-Item -ItemType File -Path $LogFile -Force -Confirm:$False -ErrorAction SilentlyContinue)
               # Set ACL for users on logfile
               $NewAcl = (Get-Acl -Path $LogFile)
               $identity = (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList S-1-5-11)
               $fileSystemRights = 'Modify'
               $type = 'Allow'
               $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
               $fileSystemAccessRule = (New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList)
               $NewAcl.SetAccessRule($fileSystemAccessRule)
               $null = (Set-Acl -Path $LogFile -AclObject $NewAcl)
            }
            catch 
            {
               Return $False
            }

            # if MaxLogFiles is 0 don't delete any old archived log files
            if (-not($MaxLogFiles -eq 0)) 
            {
               # set filter to search for archived log files
               $archivedLogFileFilter = $logFileNameWithoutExtension + '??????????????' + $logFileNameExtension

               # get archived log files
               $oldLogFiles = (Get-Item -Path "$(Join-Path -Path $logFilePath -ChildPath $archivedLogFileFilter)")

               if ([bool]$oldLogFiles) 
               {
                  # compare found log files to MaxLogFiles parameter of the log object, and delete oldest until we are
                  # back to the correct number
                  if (($oldLogFiles.Count + 1) -gt $MaxLogFiles) 
                  {
                     [int]$numTooMany = (($oldLogFiles.Count) + 1) - $MaxLogFiles
                     $null = ($oldLogFiles | Sort-Object -Property 'LastWriteTime' | Select-Object -First $numTooMany | Remove-Item -Force  -Confirm:$False -ErrorAction SilentlyContinue)
                  }
               }
            }

            # Log Header
            $Log = "##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern)`n##################################################"
            $null = ($Log | Out-File -FilePath $LogFile -Append -Force)
            Write-ToLog -LogMsg 'Running in System context'

            if ($ActivateGPOManagement) 
            {
               Write-ToLog -LogMsg 'Activated WAU GPO Management detected, comparing...'

               if ($null -ne $ChangedSettings -and $ChangedSettings -ne 0) 
               {
                  Write-ToLog -LogMsg 'Changed settings detected and applied' -LogColor 'Yellow'
               }
               else 
               {
                  Write-ToLog -LogMsg 'No Changed settings detected' -LogColor 'Yellow'
               }
            }

            Write-ToLog -LogMsg ('Max Log Size reached: {0} bytes - Rotated Logs' -f $MaxLogSize)

            Return $True
         }
      }
   }
   catch 
   {
      Return $False
   }
}
