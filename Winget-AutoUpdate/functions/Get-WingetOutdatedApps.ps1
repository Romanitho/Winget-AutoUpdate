#Function to get outdated app list, in formatted array

function Get-WingetOutdatedApps {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get list of available upgrades on winget format
    $upgradeResult = & $Winget upgrade --source winget | Out-String

    #Start Convertion of winget format to an array. Check if "-----" exists (Winget Error Handling)
    if (!($upgradeResult -match "-----")) {
        return "An unusual thing happened (maybe all apps are upgraded):`n$upgradeResult"
    }

    #Split winget output to lines (excluding lines/taking care of different scenarios in winget >= v1.4.10173)
    $lines = $upgradeResult.Split([Environment]::NewLine) | Where-Object { ($_ -and $_ -notmatch "�-�") -and ($_ -and $_ -notmatch "\bName\s+Id\s+Version\s+Available\b") -and ($_ -and $_ -notmatch "-----") -and ($_ -and $_ -notmatch "update the source:") -and ($_ -and $_ -notmatch "--include-unknown") -and ($_ -and $_ -notmatch "require explicit targeting") }

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
    For ($i = $fl + 2; $i -lt $lines.Length - 1; $i++) {
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
    if ($IsSystem -eq $false) {
        $SystemApps = Get-Content -Path "$WorkingDir\winget_system_apps.txt"
        $upgradeList = $upgradeList | Where-Object { $SystemApps -notcontains $_.Id }
    }

    return $upgradeList | Sort-Object { Get-Random }
}
