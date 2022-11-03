#Function to check Mods External Path

function Test-ModsPath ($ModsPath, $WingetUpdatePath) {
    # URL, UNC or Local Path
    # Get local and external Mods paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath"
 
    #Get File Names Locally
    $InternalModsNames = Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1

    # If path is URL
    if ($ModsPath -like "http*") {
        $ExternalMods = "$ModsPath/"
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ExternalMods").Close() | Out-Null
            $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                try {
                    $wc.DownloadFile($ExternalMods, $LocalMods)
                }
                catch {
                    return $False
                }
                return $true
            }
        }
        catch {
            return $False
        }
    }
    # If path is UNC or local
    else {
        if (Test-Path -Path $ExternalMods"\*.ps1") {
            #Get File Names Externally
            $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1
            #Delete Local Mods that doesn't exist Externally
            foreach ($Mod in $InternalModsNames){
                try {
                    If($Mod -notin $ExternalModsNames ){
                        Remove-Item $LocalMods\$Mod -Force | Out-Null
                    }
                }
                catch {
                    #Do nothing
                }
            }
            try {
                foreach ($Mod in $ExternalModsNames){
                    if (Test-Path -Path $LocalMods"\"$Mod) {
                        $dateLocalMod = (Get-Item "$LocalMods\$Mod").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $dateExternalMod = (Get-Item "$ExternalMods\$Mod").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    if ($dateExternalMod -gt $dateLocalMod) {
                        try {
                            Copy-Item $ExternalMods\$Mod -Destination $LocalMods\$Mod -Force
                            $ModsUpdated++
                        }
                        catch {
                            return $False
                        }
                    }
                }
                
            }
            catch {
                return $False
            }
            return $ModsUpdated
        }
    }
    return $False
}
