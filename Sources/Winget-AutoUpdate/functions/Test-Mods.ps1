<#
.SYNOPSIS
    Checks for application modification scripts in the mods folder.

.DESCRIPTION
    Searches for app-specific scripts that customize the install/upgrade process.
    Hooks: preinstall, override, custom, arguments, upgrade, install, installed, notinstalled.

.PARAMETER app
    The WinGet application ID to check.

.OUTPUTS
    Array: [PreInstall, Override, Custom, Arguments, Upgrade, Install, Installed, NotInstalled]
#>
function Test-Mods ($app) {

    $Mods = "$WorkingDir\mods"
    $result = @{
        PreInstall   = $null
        Override     = $null
        Custom       = $null
        Arguments    = $null
        Upgrade      = $null
        Install      = $null
        Installed    = $null
        NotInstalled = $null
    }

    # Global fallback for failed installs
    if (Test-Path "$Mods\_WAU-notinstalled.ps1") {
        $result.NotInstalled = "$Mods\_WAU-notinstalled.ps1"
    }

    # App-specific mods
    if (Test-Path "$Mods\$app-*") {
        if (Test-Path "$Mods\$app-preinstall.ps1") { $result.PreInstall = "$Mods\$app-preinstall.ps1" }
        if (Test-Path "$Mods\$app-override.txt") { $result.Override = (Get-Content "$Mods\$app-override.txt" -Raw).Trim() }
        if (Test-Path "$Mods\$app-custom.txt") { $result.Custom = (Get-Content "$Mods\$app-custom.txt" -Raw).Trim() }
        if (Test-Path "$Mods\$app-arguments.txt") { $result.Arguments = (Get-Content "$Mods\$app-arguments.txt" -Raw).Trim() }
        if (Test-Path "$Mods\$app-install.ps1") {
            $result.Install = "$Mods\$app-install.ps1"
            $result.Upgrade = "$Mods\$app-install.ps1"
        }
        if (Test-Path "$Mods\$app-upgrade.ps1") { $result.Upgrade = "$Mods\$app-upgrade.ps1" }
        if (Test-Path "$Mods\$app-installed.ps1") { $result.Installed = "$Mods\$app-installed.ps1" }
        if (Test-Path "$Mods\$app-notinstalled.ps1") { $result.NotInstalled = "$Mods\$app-notinstalled.ps1" }
    }

    return $result.PreInstall, $result.Override, $result.Custom, $result.Arguments, $result.Upgrade, $result.Install, $result.Installed, $result.NotInstalled
}
