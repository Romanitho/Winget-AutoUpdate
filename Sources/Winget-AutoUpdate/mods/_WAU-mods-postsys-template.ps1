<# Mods for WAU (postsys) - if Network is active/any Winget is installed/running as SYSTEM after SYSTEM updates
Winget-Upgrade.ps1 calls this script with the code:
[Write-ToLog "Running Mods (postsys) for WAU..." "Yellow"
& "$Mods\_WAU-mods-postsys.ps1"]
Make sure your Functions have unique names!
#>

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1

<# ARRAYS/VARIABLES #>
#Example:
#Beginning of Desktop Link Name to Remove - optional wildcard (*) after, without .lnk, multiple: "lnk1","lnk2"
#The function Remove-ModsLnk returns the number of removed links.
#$Lnk = @("Acrobat Read*","Bitwarden","calibre*")


<# MAIN #>
#Example:
# if ($Lnk) {
#     $removedCount = Remove-ModsLnk $Lnk
#     Write-ToLog "-> Removed $($removedCount) Public Desktop Links!" "Green"
# }

Write-ToLog "...nothing to do!" "Green"
