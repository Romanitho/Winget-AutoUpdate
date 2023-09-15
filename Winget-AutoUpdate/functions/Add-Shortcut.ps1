# Function to create shortcuts
function Add-Shortcut
{
   [CmdletBinding()]
   param
   (
      [string]
      $Target,
      [string]
      $Shortcut,
      [string]
      $Arguments,
      [string]
      $Icon,
      [string]
      $Description
   )
   
   $WScriptShell = (New-Object -ComObject WScript.Shell)
   $Shortcut = $WScriptShell.CreateShortcut($Shortcut)
   $Shortcut.TargetPath = $Target
   $Shortcut.Arguments = $Arguments
   $Shortcut.IconLocation = $Icon
   $Shortcut.Description = $Description
   $Shortcut.Save()
}
