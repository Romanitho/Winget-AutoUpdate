# Function to configure the prefered scope option as Machine
function Add-ScopeMachine
{
   [CmdletBinding()]
   param
   (
      [string]
      $SettingsPath
   )

   if (Test-Path -Path $SettingsPath -ErrorAction SilentlyContinue)
   {
      $ConfigFile = (Get-Content -Path $SettingsPath -ErrorAction SilentlyContinue | Where-Object -FilterScript {
            ($_ -notmatch '//')
         } | ConvertFrom-Json)
   }

   if (!$ConfigFile)
   {
      $ConfigFile = @{
      }
   }

   if ($ConfigFile.installBehavior.preferences.scope)
   {
      $ConfigFile.installBehavior.preferences.scope = 'Machine'
   }
   else
   {
      $Scope = (New-Object -TypeName PSObject -Property $(@{
               scope = 'Machine'
            }))
      $Preference = (New-Object -TypeName PSObject -Property $(@{
               preferences = $Scope
            }))
      $null = (Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force)
   }

   $null = ($ConfigFile | ConvertTo-Json | Out-File -FilePath $SettingsPath -Encoding utf8 -Force -Confirm:$false)
}
