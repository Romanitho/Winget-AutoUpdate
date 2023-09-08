<# #Mods for WAU (if Network is active/any Winget is installed/running as SYSTEM)
Winget-Upgrade.ps1 calls this script with the code:
[Write-ToLog "Running Mods for WAU..." "Yellow"
& "$Mods\_WAU-mods.ps1"]
Make sure your Functions have unique names!
Exit 1 to Re-run WAU from this script!
#>

<# FUNCTIONS #>


<# ARRAYS/VARIABLES #>


<# MAIN #>


Write-ToLog "...everything's already been done!" "Green"
Exit 0
