#Function to get outdated app list, in formatted array

function Get-WingetOutdatedApps {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get list of available upgrades on winget format
    Write-Log "Checking application updates on Winget Repository..." "yellow"
    $upgradeResult = & $Winget upgrade --source winget | Out-String

    #Start Convertion of winget format to an array. Check if "-----" exists
    if (!($upgradeResult -match "-----")) {
        return
    }

    #Split winget output to lines
    $lines = $upgradeResult.Split([Environment]::NewLine) | Where-Object { $_ -and $_ -notmatch "--include-unknown" }

    # Find the line that starts with "------"
    $fl = 0
    while (-not $lines[$fl].StartsWith("-----")) {
        $fl++
    }
    
    #Get header line 
    $fl = $fl - 1

    #Get header titles
    $index = $lines[$fl] -split '\s+'

    # Line $fl has the header, we can find char where we find ID and Version
    $idStart = $lines[$fl].IndexOf($index[1])
    $versionStart = $lines[$fl].IndexOf($index[2])
    $availableStart = $lines[$fl].IndexOf($index[3])

    # Now cycle in real package and split accordingly
    $upgradeList = @()
    For ($i = $fl + 2; $i -lt $lines.Length -1; $i++) {
        $line = $lines[$i]
        if ($line) {
            $software = [Software]::new()
            $software.Name = $line.Substring(0, $idStart).TrimEnd()
            $software.Id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
            $software.Version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
            $software.AvailableVersion = $line.Substring($availableStart).TrimEnd()
            #add formated soft to list
            $upgradeList += $software
        }
    }

    #If current user is not system, remove system apps from list
    if ($currentPrincipal -eq $true) {
        $SystemApps = Get-Content -Path "$WorkingDir\winget_system_apps.txt"
        $upgradeList = $upgradeList | Where-Object {$SystemApps -notcontains $_}
    }
    else {
        Get-WingetSystemApps
    }

    return $upgradeList | Sort-Object {Get-Random}
}
