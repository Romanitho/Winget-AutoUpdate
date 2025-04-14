<# Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM)
Winget-Upgrade.ps1 calls this script with the code:
[Write-ToLog "Running Mods for WAU..." "Yellow"
& "$Mods\_WAU-mods.ps1"]
Make sure your Functions have unique names!
Exit 1 to Re-run WAU from this script (beware of loops)!
#>

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1


<# ARRAYS/VARIABLES #>


<# MAIN #>


Write-ToLog "...nothing to do!" "Green"
Exit 0
