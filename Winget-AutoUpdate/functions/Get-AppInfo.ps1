# Get the winget App Information

function Get-AppInfo
{
   # Get AppID Info
   [CmdletBinding()]
   param
   (
      [string]
      $AppID
   )

   $String = (& $winget show $AppID --accept-source-agreements -s winget | Out-String)
   # Search for Release Note info
   $ReleaseNote = [regex]::match($String, '(?<=Release Notes Url: )(.*)(?=\n)').Groups[0].Value

   # Return Release Note
   return $ReleaseNote
}
