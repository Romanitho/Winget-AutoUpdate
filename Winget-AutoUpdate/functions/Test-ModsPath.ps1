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
        #Get Index of $ExternalMods (or index page with href listing of all the Mods)
        try {
            $WebResponse = Invoke-WebRequest -Uri $ExternalMods
        }
        catch {
            return $False
        }

        # Collect the external list of href links
        $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty href
        #Delete Local Mods that don't exist Externally
        foreach ($Mod in $InternalModsNames) {
            If ($Mod -notin $ModLinks) {
                Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                $DeletedMods++
            }
        }

        #Loop through all links
        $WebResponse.Links | Select-Object -ExpandProperty href | ForEach-Object {
            #Check for .ps1 in listing/HREF:s in an index page pointing to .ps1
            if ($_ -like "*.ps1") {
                try {
                    $dateExternalMod = ""
                    $dateLocalMod =""
                    $wc.OpenRead("$ExternalMods/$_").Close() | Out-Null
                    $dateExternalMod = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
                    if (Test-Path -Path $LocalMods"\"$_) {
                        $dateLocalMod = (Get-Item "$LocalMods\$_").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
        
                    if ($dateExternalMod -gt $dateLocalMod) {
                        try {
                            $SaveMod = Join-Path -Path "$LocalMods\" -ChildPath $_
                            $Mod = '{0}/{1}' -f $ModsPath.TrimEnd('/'), $_
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
        return $ModsUpdated, $DeletedMods
    }
    # If path is UNC or local
    else {
        if (Test-Path -Path $ExternalMods"\*.ps1") {
            #Get File Names Externally
            $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1
            #Delete Local Mods that don't exist Externally
            foreach ($Mod in $InternalModsNames){
                If($Mod -notin $ExternalModsNames ){
                    Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                    $DeletedMods++
                }
            }
            try {
                foreach ($Mod in $ExternalModsNames){
                    if (Test-Path -Path $LocalMods"\"$Mod) {
                        $dateLocalMod = (Get-Item "$LocalMods\$Mod").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $dateExternalMod = (Get-Item "$ExternalMods\$Mod").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    if ($dateExternalMod -gt $dateLocalMod) {
                        Copy-Item $ExternalMods\$Mod -Destination $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                        $ModsUpdated++
                    }
                }
                
            }
            catch {
                return $False
            }
            return $ModsUpdated, $DeletedMods
        }
        return $False
    }
}
