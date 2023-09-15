# Function to check the connectivity

function Test-Network 
{
   #Init
    
   $timeout = 0

   # Test connectivity during 30 min then timeout
   Write-ToLog -LogMsg 'Checking internet connection...' -LogColor 'Yellow'
   While ($timeout -lt 1800) 
   {
      $URLtoTest = 'https://raw.githubusercontent.com/Romanitho/Winget-AutoUpdate/main/LICENSE'
      $URLcontent = ((Invoke-WebRequest -Uri $URLtoTest -UseBasicParsing).content)

      if ($URLcontent -like '*MIT License*') 
      {
         Write-ToLog -LogMsg 'Connected !' -LogColor 'Green'

         # Check for metered connection
         $null = (Add-Type -AssemblyName Windows.Networking)
         $null = [Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType = WindowsRuntime]
         $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost()

         if ($cost.ApproachingDataLimit -or $cost.OverDataLimit -or $cost.Roaming -or $cost.BackgroundDataUsageRestricted -or ($cost.NetworkCostType -ne 'Unrestricted')) 
         {
            Write-ToLog -LogMsg 'Metered connection detected.' -LogColor 'Yellow'

            if ($WAUConfig.WAU_DoNotRunOnMetered -eq 1) 
            {
               Write-ToLog -LogMsg 'WAU is configured to bypass update checking on metered connection'
               return $false
            }
            else 
            {
               Write-ToLog -LogMsg 'WAU is configured to force update checking on metered connection'
               return $true
            }
         }
         else 
         {
            return $true
         }
      }
      else 
      {
         Start-Sleep -Seconds 10
         $timeout += 10

         # Send Warning Notif if no connection for 5 min
         if ($timeout -eq 300) 
         {
            # Log
            Write-ToLog -LogMsg "Notify 'No connection' sent." -LogColor 'Yellow'

            # Notif
            $Title = $NotifLocale.local.outputs.output[0].title
            $Message = $NotifLocale.local.outputs.output[0].message
            $MessageType = 'warning'
            $Balise = 'Connection'
            Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise
         }
      }
   }

   # Send Timeout Notif if no connection for 30 min
   Write-ToLog -LogMsg 'Timeout. No internet connection !' -LogColor 'Red'

   # Notif
   $Title = $NotifLocale.local.outputs.output[1].title
   $Message = $NotifLocale.local.outputs.output[1].message
   $MessageType = 'error'
   $Balise = 'Connection'
   Start-NotifTask -Title $Title -Message $Message -MessageType $MessageType -Balise $Balise

   return $false
}
