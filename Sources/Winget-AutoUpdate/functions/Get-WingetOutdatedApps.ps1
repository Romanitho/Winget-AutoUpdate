#Function to get the outdated app list, in formatted array

function Get-WingetOutdatedApps {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get list of available upgrades on winget format
    $upgradeResult = & $Winget upgrade --source winget | Where-Object { $_ -notlike "   *" } | Out-String

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

        return $upgradeList | Sort-Object { Get-Random }

    }

}
