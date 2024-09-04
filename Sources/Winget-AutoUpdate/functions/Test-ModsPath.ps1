#Function to check mods External Path

function Test-ModsPath ($ModsPath, $WingetUpdatePath, $AzureBlobSASURL) {
    # URL, UNC or Local Path
    # Get local and external Mods paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath"

    #Get File Names Locally
    $InternalModsNames = Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1, *.txt
    $InternalBinsNames = Get-ChildItem -Path $LocalMods"\bins" -Name -Recurse -Include *.exe

    # If path is URL
    if ($ExternalMods -like "http*") {
        # ADD TLS 1.2 and TLS 1.1 to list of currently used protocols
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; #DevSkim: ignore DS440020,DS440020 Hard-coded SSL/TLS Protocol 
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls11; #DevSkim: ignore DS440020,DS440020 Hard-coded SSL/TLS Protocol
        #Get Index of $ExternalMods (or index page with href listing of all the Mods)
        try {
            $WebResponse = Invoke-WebRequest -Uri $ExternalMods -UseBasicParsing
        }
        catch {
            $Script:ReachNoPath = $True
            return $False
        }

        #Check for bins, download if newer. Delete if not external
        $ExternalBins = "$ModsPath/bins"
        if ($WebResponse -match "bins/") {
            $BinResponse = Invoke-WebRequest -Uri $ExternalBins -UseBasicParsing
            # Collect the external list of href links
            $BinLinks = $BinResponse.Links | Select-Object -ExpandProperty HREF
            #If there's a directory path in the HREF:s, delete it (IIS)
            $CleanBinLinks = $BinLinks -replace "/.*/", ""
            #Modify strings to HREF:s
            $index = 0
            foreach ($Bin in $CleanBinLinks) {
                if ($Bin) {
                    $CleanBinLinks[$index] = '<a href="' + $Bin + '"> ' + $Bin + '</a>'
                }
                $index++
            }
            #Delete Local Bins that don't exist Externally
            $index = 0
            $CleanLinks = $BinLinks -replace "/.*/", ""
            foreach ($Bin in $InternalBinsNames) {
                If ($CleanLinks -notcontains "$Bin") {
                    Remove-Item $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue | Out-Null
                }
                $index++
            }
            $CleanBinLinks = $BinLinks -replace "/.*/", ""
            $Bin = ""
            #Loop through all links
            $wc = New-Object System.Net.WebClient
            $CleanBinLinks | ForEach-Object {
                #Check for .exe in listing/HREF:s in an index page pointing to .exe
                if ($_ -like "*.exe") {
                    $dateExternalBin = ""
                    $dateLocalBin = ""
                    $wc.OpenRead("$ExternalBins/$_").Close() | Out-Null
                    $dateExternalBin = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
                    if (Test-Path -Path $LocalMods"\bins\"$_) {
                        $dateLocalBin = (Get-Item "$LocalMods\bins\$_").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    if ($dateExternalBin -gt $dateLocalBin) {
                        $SaveBin = Join-Path -Path "$LocalMods\bins" -ChildPath $_
                        Invoke-WebRequest -Uri "$ExternalBins/$_" -OutFile $SaveBin.Replace("%20", " ") -UseBasicParsing
                    }
                }
            }
        }

        # Collect the external list of href links
        $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty HREF

        #If there's a directory path in the HREF:s, delete it (IIS)
        $CleanLinks = $ModLinks -replace "/.*/", ""

        #Modify strings to HREF:s
        $index = 0
        foreach ($Mod in $CleanLinks) {
            if ($Mod) {
                $CleanLinks[$index] = '<a href="' + $Mod + '"> ' + $Mod + '</a>'
            }
            $index++
        }

        #Delete Local Mods that don't exist Externally
        $DeletedMods = 0
        $index = 0
        $CleanLinks = $ModLinks -replace "/.*/", ""
        foreach ($Mod in $InternalModsNames) {
            If ($CleanLinks -notcontains "$Mod") {
                Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                $DeletedMods++
            }
            $index++
        }

        $CleanLinks = $ModLinks -replace "/.*/", ""

        #Loop through all links
        $wc = New-Object System.Net.WebClient
        $CleanLinks | ForEach-Object {
            #Check for .ps1/.txt in listing/HREF:s in an index page pointing to .ps1/.txt
            if (($_ -like "*.ps1") -or ($_ -like "*.txt")) {
                try {
                    $dateExternalMod = ""
                    $dateLocalMod = ""
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
                            $Script:ReachNoPath = $True
                        }
                    }
                }
                catch {
                    if (($_ -like "*.ps1") -or ($_ -like "*.txt")) {
                        $Script:ReachNoPath = $True
                    }
                }
            }
        }
        return $ModsUpdated, $DeletedMods
    }
    # If Path is Azure Blob
    elseif ($ExternalMods -like "AzureBlob") {
        Write-ToLog "Azure Blob Storage set as mod source"
        Write-ToLog "Checking AZCopy"
        Get-AZCopy $WingetUpdatePath
        #Safety check to make sure we really do have azcopy.exe and a Blob URL
        if ((Test-Path -Path "$WingetUpdatePath\azcopy.exe" -PathType Leaf) -and ($null -ne $AzureBlobSASURL)) {
            Write-ToLog "Syncing Blob storage with local storage"

            $AZCopySyncOutput = & $WingetUpdatePath\azcopy.exe sync "$AzureBlobSASURL" "$LocalMods" --from-to BlobLocal --delete-destination=true
            $AZCopyOutputLines = $AZCopySyncOutput.Split([Environment]::NewLine)

            foreach ( $_ in $AZCopyOutputLines) {
                $AZCopySyncAdditionsRegex = [regex]::new("(?<=Number of Copy Transfers Completed:\s+)\d+")
                $AZCopySyncDeletionsRegex = [regex]::new("(?<=Number of Deletions at Destination:\s+)\d+")
                $AZCopySyncErrorRegex = [regex]::new("^Cannot perform sync due to error:")

                $AZCopyAdditions = [int] $AZCopySyncAdditionsRegex.Match($_).Value
                $AZCopyDeletions = [int] $AZCopySyncDeletionsRegex.Match($_).Value

                if ($AZCopyAdditions -ne 0) {
                    $ModsUpdated = $AZCopyAdditions
                }

                if ($AZCopyDeletions -ne 0) {
                    $DeletedMods = $AZCopyDeletions
                }

                if ($AZCopySyncErrorRegex.Match($_).Value) {
                    Write-ToLog  "AZCopy Sync Error! $_"
                }
            }
        }
        else {
            Write-ToLog "Error 'azcopy.exe' or SAS Token not found!"
        }

        return $ModsUpdated, $DeletedMods
    }
    # If path is UNC or local
    else {
        $ExternalBins = "$ModsPath\bins"
        if (Test-Path -Path $ExternalBins"\*.exe") {
            $ExternalBinsNames = Get-ChildItem -Path $ExternalBins -Name -Recurse -Include *.exe
            #Delete Local Bins that don't exist Externally
            foreach ($Bin in $InternalBinsNames) {
                If ($Bin -notin $ExternalBinsNames ) {
                    Remove-Item $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            #Copy newer external bins
            foreach ($Bin in $ExternalBinsNames) {
                $dateExternalBin = ""
                $dateLocalBin = ""
                if (Test-Path -Path $LocalMods"\bins\"$Bin) {
                    $dateLocalBin = (Get-Item "$LocalMods\bins\$Bin").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
                $dateExternalBin = (Get-Item "$ExternalBins\$Bin").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                if ($dateExternalBin -gt $dateLocalBin) {
                    Copy-Item $ExternalBins\$Bin -Destination $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }

        if ((Test-Path -Path $ExternalMods"\*.ps1") -or (Test-Path -Path $ExternalMods"\*.txt")) {
            #Get File Names Externally
            $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1, *.txt

            #Delete Local Mods that don't exist Externally
            $DeletedMods = 0
            foreach ($Mod in $InternalModsNames) {
                If ($Mod -notin $ExternalModsNames ) {
                    Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                    $DeletedMods++
                }
            }

            #Copy newer external mods
            foreach ($Mod in $ExternalModsNames) {
                $dateExternalMod = ""
                $dateLocalMod = ""
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
        else {
            $Script:ReachNoPath = $True
        }
        return $ModsUpdated, $DeletedMods
    }
}
