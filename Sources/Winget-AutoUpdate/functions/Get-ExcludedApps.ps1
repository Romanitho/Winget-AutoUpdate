<#
.SYNOPSIS
    Retrieves the list of excluded (blacklisted) applications.

.DESCRIPTION
    Returns application IDs to exclude from automatic updates.
    Priority: GPO registry > local file > default file.

.OUTPUTS
    Array of application IDs to exclude.
#>
function Get-ExcludedApps {

    $GPOPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\BlackList"
    $LocalFile = "$WorkingDir\excluded_apps.txt"
    $DefaultFile = "$WorkingDir\config\default_excluded_apps.txt"

    # GPO takes priority
    if (Test-Path $GPOPath) {
        Write-ToLog "-> Excluded apps from GPO is activated"
        $AppIDs = (Get-Item $GPOPath).Property | ForEach-Object {
            $id = (Get-ItemPropertyValue $GPOPath -Name $_).Trim()
            Write-ToLog "Exclude app $id"
            $id
        }
    }
    elseif (Test-Path $LocalFile) {
        Write-ToLog "-> Successfully loaded local excluded apps list."
        $AppIDs = (Get-Content $LocalFile).Trim()
    }
    elseif (Test-Path $DefaultFile) {
        Write-ToLog "-> Successfully loaded default excluded apps list."
        $AppIDs = (Get-Content $DefaultFile).Trim()
    }

    return $AppIDs | Where-Object { $_ }
}
