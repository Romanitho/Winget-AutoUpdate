<#
.SYNOPSIS
    Gets WAU configuration including GPO overrides.

.DESCRIPTION
    Reads settings from registry, applying GPO policies if present.

.OUTPUTS
    PSCustomObject with WAU configuration properties.
#>
Function Get-WAUConfig {

    # Get base config (newest version from registry)
    $WAUConfig = Get-ItemProperty "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate*", "HKLM:\SOFTWARE\WOW6432Node\Romanitho\Winget-AutoUpdate*" -ErrorAction SilentlyContinue |
        Sort-Object { $_.ProductVersion } -Descending |
        Select-Object -First 1

    # Apply GPO overrides if present
    $GPO = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate" -ErrorAction SilentlyContinue
    if ($GPO) {
        Write-ToLog "GPO policies detected - applying" "Yellow"
        $GPO.PSObject.Properties | ForEach-Object { $WAUConfig.PSObject.Properties.add($_) }
    }

    return $WAUConfig
}
