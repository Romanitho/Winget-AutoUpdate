<# Mods for WAU (postsys) - if Network is active/any Winget is installed/running as SYSTEM after SYSTEM updates
Winget-Upgrade.ps1 calls this script with the code:
[Write-ToLog "Running Mods (postsys) for WAU..." "Yellow"
& "$Mods\_WAU-mods-postsys.ps1"]
Make sure your Functions have unique names!
#>

<# FUNCTIONS #>


<# ARRAYS/VARIABLES #>


<# MAIN #>

Write-ToLog "...nothing to do!" "Green"
