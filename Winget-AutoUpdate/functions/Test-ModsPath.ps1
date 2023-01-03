#Function to check Mods External Path

function Test-ModsPath ($ModsPath, $WingetUpdatePath) {
    # URL, UNC or Local Path
    # Get local and external Mods paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath"
 
    #Get File Names Locally
    $InternalModsNames = Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1, *.txt

    # If path is URL
    if ($ExternalMods -like "http*") {
        $wc = New-Object System.Net.WebClient

        # enable TLS 1.2 and TLS 1.1 protocols
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11
        #Get Index of $ExternalMods (or index page with href listing of all the Mods)
        try {
            $WebResponse = Invoke-WebRequest -Uri $ExternalMods -UseBasicParsing
        }
        catch {
            return $False
        }

        # Collect the external list of href links
        $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty href

        #If there's a directory path in the HREF:s, delete it (IIS)
        $ModLinks -replace "/.*/", ""
        #$ModLinks -add <a href='"' + $ModLinks + "\">"" + $$ModLinks + "</a>"

        #<a href="Microsoft.PowerToys-installed.ps1"> Microsoft.PowerToys-installed.ps1</a>
        #<A HREF="/wau/mods/Microsoft.PowerToys-installed.ps1">Microsoft.PowerToys-installed.ps1</A>
        #(\x3Ca\x20href=\x22)(.*|.*)

        #Delete Local Mods that don't exist Externally
        foreach ($Mod in $InternalModsNames) {
            If ($Mod -notin $ModLinks) {
                Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                $DeletedMods++
            }
        }

        #Loop through all links
        $WebResponse.Links | Select-Object -ExpandProperty href | ForEach-Object {
            #Check for .ps1/.txt in listing/HREF:s in an index page pointing to .ps1/.txt
            if (($_ -like "*.ps1") -or ($_ -like "*.txt")) {
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
                            Invoke-WebRequest -Uri "$Mod" -OutFile $SaveMod -UseBasicParsing
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
        if ((Test-Path -Path $ExternalMods"\*.ps1") -or (Test-Path -Path $ExternalMods"\*.txt")) {
            #Get File Names Externally
            $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1, *.txt
            #Delete Local Mods that don't exist Externally
            foreach ($Mod in $InternalModsNames){
                If($Mod -notin $ExternalModsNames ){
                    Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                    $DeletedMods++
                }
            }
            try {
                foreach ($Mod in $ExternalModsNames){
                    $dateExternalMod = ""
                    $dateLocalMod =""
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
