<# An all-purpose mod for doing things
if an AppID upgrade/install in WAU fails
Name it:
"$Mods\_WAU-notinstalled.ps1"

This all-purpose mod will be overridden by any specific:
"$Mods\AppID-notinstalled.ps1"
#>

<# FUNCTIONS #>
. $PSScriptRoot\_Mods-Functions.ps1

<# ARRAYS/VARIABLES #>


<# MAIN #>
if ($($app.Id) -eq "Microsoft.SQLServerManagementStudio") {
	if ($ConfirmInstall -eq $false) {
		try {
			Write-ToLog "...successfully done something" "Green"
		}
		catch {
			Write-ToLog "...failed to do something" "Red"
		}
	}
}
else {
	Write-ToLog "...nothing defined for $($app.Id)" "Yellow"
}
