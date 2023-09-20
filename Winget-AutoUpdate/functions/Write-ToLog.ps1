# Write to Log Function

function Write-ToLog
{
   # Get log
   [CmdletBinding()]
   param
   (
      [string]
      $LogMsg,
      [string]
      $LogColor = 'White'
   )

   $Log = ('{0} - {1}' -f (Get-Date -UFormat '%T'), $LogMsg)

   #Echo log
   $Log | Write-Host -ForegroundColor $LogColor

   #Write log to file
   $Log | Out-File -FilePath $LogFile -Append -Force -Confirm:$false
}
