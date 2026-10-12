<#
.SYNOPSIS
    Retrieves the list of included (whitelisted) applications.

.DESCRIPTION
    Returns application IDs to include in automatic updates (whitelist mode).
    Priority: GPO registry > local file.

.OUTPUTS
    Array of application IDs to include.
#>
function Get-IncludedApps {

    $GPOPath = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate\WhiteList"
    $LocalFile = "$WorkingDir\included_apps.txt"

    # GPO takes priority
    if (Test-Path $GPOPath) {
        Write-ToLog "-> Included apps from GPO is activated"
        $AppIDs = (Get-Item $GPOPath).Property | ForEach-Object {
            $id = (Get-ItemPropertyValue $GPOPath -Name $_).Trim()
            Write-ToLog "Include app $id"
            $id
        }
    }
    elseif (Test-Path $LocalFile) {
        Write-ToLog "-> Successfully loaded local included apps list: $LocalFile"
        $AppIDs = (Get-Content $LocalFile -ErrorAction SilentlyContinue) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    }
    elseif ($env:ProgramData -and (Test-Path ([System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'included_apps.txt')))) {
        $ProgramDataFile = [System.IO.Path]::Combine($env:ProgramData, 'Winget-AutoUpdate', 'included_apps.txt')
        Write-ToLog "-> Successfully loaded shared included apps list: $ProgramDataFile"
        $AppIDs = (Get-Content $ProgramDataFile -ErrorAction SilentlyContinue) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    }

    return @($AppIDs | Where-Object { $_ } | Select-Object -Unique)
}
