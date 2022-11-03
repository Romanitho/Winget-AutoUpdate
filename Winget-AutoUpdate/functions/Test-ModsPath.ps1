#Function to check Mods External Path

function Test-ModsPath ($ModsPath, $WingetUpdatePath) {
    # URL, UNC or Local Path
    # Get local and external Mods paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath"
 
    #Get File Names Locally
    $InternalModsNames = Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1

    # If path is URL
    if ($ExternalMods -like "http*") {
        $wc = New-Object System.Net.WebClient

        # enable TLS 1.2 and TLS 1.1 protocols
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11
        #Get Index of $ExternalMods (or index page with href listings of all the Mods)
        $WebResponse = Invoke-WebRequest -Uri $ExternalMods
        # Get the list of links, skip the first one ("../") if listing is allowed
        $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty href -Skip 1
        
        #Delete Local Mods that doesn't exist Externally
        foreach ($Mod in $InternalModsNames) {
            try {
                If ($Mod -notin $ModLinks) {
                    Remove-Item $LocalMods\$Mod -Force | Out-Null
                }
            }
            catch {
                #Do nothing
            }
        }
        
        #Loop through all links
        $WebResponse.Links | Select-Object -ExpandProperty href -Skip 1 | ForEach-Object {
            #Check for .ps1 in listing/HREF:s in an index page pointing to .ps1
            if ($_ -like "*.ps1") {
                try {
                    $wc.OpenRead("$ExternalMods/$_").Close() | Out-Null
                    $dateExternalMod = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
                    if (Test-Path -Path $LocalMods"\"$_) {
                        $dateLocalMod = (Get-Item "$LocalMods\$_").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
        
                    if ($dateExternalMod -gt $dateLocalMod) {
                        try {
                            $SaveMod = Join-Path -Path "$LocalMods\" -ChildPath $_
                            $Mod = '{0}/{1}' -f $ModsPath.TrimEnd('/'), $_
                            #Write-Host "Downloading file $dateExternal -  $ExternalMods/$_ to $SaveMod"
                            Invoke-WebRequest -Uri "$Mod" -OutFile $SaveMod
                            $ModsUpdated++
                        }
                        catch {
                            return $False
                        }
                    }
                }
                catch {
                    return $False
                }
            }
        }
        return $ModsUpdated
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
