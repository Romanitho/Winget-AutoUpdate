#Function to get the outdated app list, in formatted array

function Get-WingetOutdatedApps {

    Param(
        [Parameter(Position = 0, Mandatory = $True, HelpMessage = "You MUST supply value for winget repo, we need it")]
        [ValidateNotNullorEmpty()]
        [string]$src,
        
        [Parameter(Position = 1, Mandatory = $False, HelpMessage = "Array of pinned apps to exclude")]
        [array]$ExcludePinnedApps = @()
    )
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get list of available upgrades on winget format
    try {
        $upgradeResult = & $Winget upgrade --source $src | Where-Object { $_ -notlike "   *" } | Out-String
    }
    catch {
        Write-ToLog "Error while recieving winget upgrade list: $_" "Red"
        $upgradeResult = $null
    }

    #Start Conversion of winget format to an array. Check if "-----" exists (Winget Error Handling)
    if (!($upgradeResult -match "-----")) {

        return "No update found. 'Winget upgrade' output:`n$upgradeResult"

    }
    else {

        #Split winget output to lines
        $lines = $upgradeResult.Split([Environment]::NewLine) | Where-Object { $_ }

        # Find the line that starts with "------"
        $fl = 0
        while (-not $lines[$fl].StartsWith("-----")) {
            $fl++
        }

        #Get header line
        $fl = $fl - 1

        #Get header titles [without remove separator]
        $index = $lines[$fl] -split '(?<=\s)(?!\s)'

        # Line $fl has the header, we can find char where we find ID and Version [and manage non latin characters]
        $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
        $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
        $availableStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length

        # Now cycle in real package and split accordingly
        $upgradeList = @()
        For ($i = $fl + 2; $i -lt $lines.Length; $i++) {
            $line = $lines[$i] -replace "[\u2026]", " " #Fix "..." in long names
            if ($line.StartsWith("-----")) {
                #Get header line
                $fl = $i - 1

                #Get header titles [without remove separator]
                $index = $lines[$fl] -split '(?<=\s)(?!\s)'

                # Line $fl has the header, we can find char where we find ID and Version [and manage non latin characters]
                $idStart = $($index[0] -replace '[\u4e00-\u9fa5]', '**').Length
                $versionStart = $idStart + $($index[1] -replace '[\u4e00-\u9fa5]', '**').Length
                $availableStart = $versionStart + $($index[2] -replace '[\u4e00-\u9fa5]', '**').Length
            }
            #(Alphanumeric | Literal . | Alphanumeric) - the only unique thing in common for lines with applications
            if ($line -match "\w\.\w") {
                $software = [Software]::new()
                #Manage non latin characters
                $nameDeclination = $($line.Substring(0, $idStart) -replace '[\u4e00-\u9fa5]', '**').Length - $line.Substring(0, $idStart).Length
                $software.Name = $line.Substring(0, $idStart - $nameDeclination).TrimEnd()
                $software.Id = $line.Substring($idStart - $nameDeclination, $versionStart - $idStart).TrimEnd()
                $software.Version = $line.Substring($versionStart - $nameDeclination, $availableStart - $versionStart).TrimEnd()
                $software.AvailableVersion = $line.Substring($availableStart - $nameDeclination).TrimEnd()
                #add formatted soft to list
                $upgradeList += $software
            }
        }

        #If current user is not system, remove system apps from list
        if ($IsSystem -eq $false) {
            $SystemApps = Get-Content -Path "$WorkingDir\config\winget_system_apps.txt" -ErrorAction SilentlyContinue
            $upgradeList = $upgradeList | Where-Object { $SystemApps -notcontains $_.Id }
        }

        #Exclude pinned apps from the upgrade list
        if ($ExcludePinnedApps.Count -gt 0) {
            $pinnedAppIds = $ExcludePinnedApps | Select-Object -ExpandProperty AppId
            $originalCount = $upgradeList.Count
            $upgradeList = $upgradeList | Where-Object { $pinnedAppIds -notcontains $_.Id }
            $excludedCount = $originalCount - $upgradeList.Count
            
            if ($excludedCount -gt 0) {
                Write-ToLog "Excluded $excludedCount pinned app(s) from upgrade list" "Gray"
            }
            
            #If all apps were excluded due to pinning, return appropriate message
            if ($upgradeList.Count -eq 0 -and $originalCount -gt 0) {
                return "No update found. All $originalCount available update(s) were excluded because applications are pinned."
            }
        }

        return $upgradeList | Sort-Object { Get-Random }

    }

}
