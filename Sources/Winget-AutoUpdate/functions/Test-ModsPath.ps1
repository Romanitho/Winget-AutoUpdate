<#
.SYNOPSIS
    Syncs modification scripts from an external source.

.DESCRIPTION
    Compares local mods folder with an external source and syncs changes.
    Supports three source types:
    - HTTP/HTTPS URLs (requires directory listing)
    - Azure Blob Storage (uses AzCopy)
    - UNC/local paths

    Downloads newer files and removes local files that don't exist externally.

.PARAMETER ModsPath
    The external mods path (URL, "AzureBlob", UNC, or local path).

.PARAMETER WingetUpdatePath
    The local WAU installation directory.

.PARAMETER AzureBlobSASURL
    Optional Azure Blob Storage URL with SAS token for AzureBlob mode.

.OUTPUTS
    Array: [ModsUpdated count, DeletedMods count]

.EXAMPLE
    $result = Test-ModsPath "https://myserver.com/mods" "C:\Program Files\Winget-AutoUpdate"

.NOTES
    Sets script-scoped $ReachNoPath to True if external path is unreachable.
    Handles both .ps1/.txt mod files and .exe binaries in bins subfolder.
#>
function Test-ModsPath ($ModsPath, $WingetUpdatePath, $AzureBlobSASURL) {

    # Build local and external paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath"

    # Get list of local mod files and binaries
    $InternalModsNames = Get-ChildItem -Path $LocalMods -Name -Recurse -Include *.ps1, *.txt
    $InternalBinsNames = Get-ChildItem -Path $LocalMods"\bins" -Name -Recurse -Include *.exe

    # === Handle HTTP/HTTPS URLs ===
    if ($ExternalMods -like "http*") {
        # Enable TLS 1.2 and TLS 1.1 for secure connections
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 #DevSkim: ignore DS440020,DS440020 Hard-coded SSL/TLS Protocol
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls11 #DevSkim: ignore DS440020,DS440020 Hard-coded SSL/TLS Protocol

        # Get directory listing from web server
        try {
            $WebResponse = Invoke-WebRequest -Uri $ExternalMods -UseBasicParsing
        }
        catch {
            $Script:ReachNoPath = $True
            return $False
        }

        # --- Handle bins subfolder (executables) ---
        $ExternalBins = "$ModsPath/bins"
        if ($WebResponse -match "bins/") {
            $BinResponse = Invoke-WebRequest -Uri $ExternalBins -UseBasicParsing
            $BinLinks = $BinResponse.Links | Select-Object -ExpandProperty HREF

            # Clean directory paths from HREFs (IIS compatibility)
            $CleanBinLinks = $BinLinks -replace "/.*/", ""

            # Build HREF strings for comparison
            $index = 0
            foreach ($Bin in $CleanBinLinks) {
                if ($Bin) {
                    $CleanBinLinks[$index] = '<a href="' + $Bin + '"> ' + $Bin + '</a>'
                }
                $index++
            }

            # Delete local bins that don't exist externally
            $CleanLinks = $BinLinks -replace "/.*/", ""
            foreach ($Bin in $InternalBinsNames) {
                If ($CleanLinks -notcontains "$Bin") {
                    Remove-Item $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }

            # Download newer external bins
            $CleanBinLinks = $BinLinks -replace "/.*/", ""
            $wc = New-Object System.Net.WebClient
            $CleanBinLinks | ForEach-Object {
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

        # --- Handle mod files (.ps1, .txt) ---
        $ModLinks = $WebResponse.Links | Select-Object -ExpandProperty HREF
        $CleanLinks = $ModLinks -replace "/.*/", ""

        # Build HREF strings for comparison
        $index = 0
        foreach ($Mod in $CleanLinks) {
            if ($Mod) {
                $CleanLinks[$index] = '<a href="' + $Mod + '"> ' + $Mod + '</a>'
            }
            $index++
        }

        # Delete local mods that don't exist externally
        $DeletedMods = 0
        $CleanLinks = $ModLinks -replace "/.*/", ""
        foreach ($Mod in $InternalModsNames) {
            If ($CleanLinks -notcontains "$Mod") {
                Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                $DeletedMods++
            }
        }

        # Download newer external mods
        $CleanLinks = $ModLinks -replace "/.*/", ""
        $wc = New-Object System.Net.WebClient
        $CleanLinks | ForEach-Object {
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
    # === Handle Azure Blob Storage ===
    elseif ($ExternalMods -like "AzureBlob") {
        Write-ToLog "Azure Blob Storage set as mod source"
        Write-ToLog "Checking AZCopy"
        Get-AZCopy $WingetUpdatePath

        # Verify AzCopy and SAS URL are available
        if ((Test-Path -Path "$WingetUpdatePath\azcopy.exe" -PathType Leaf) -and ($null -ne $AzureBlobSASURL)) {
            Write-ToLog "Syncing Blob storage with local storage"

            # Run AzCopy sync with delete option
            $AZCopySyncOutput = & $WingetUpdatePath\azcopy.exe sync "$AzureBlobSASURL" "$LocalMods" --from-to BlobLocal --delete-destination=true
            $AZCopyOutputLines = $AZCopySyncOutput.Split([Environment]::NewLine)

            # Parse AzCopy output for statistics
            foreach ($line in $AZCopyOutputLines) {
                $AZCopySyncAdditionsRegex = [regex]::new("(?<=Number of Copy Transfers Completed:\s+)\d+")
                $AZCopySyncDeletionsRegex = [regex]::new("(?<=Number of Deletions at Destination:\s+)\d+")
                $AZCopySyncErrorRegex = [regex]::new("^Cannot perform sync due to error:")

                $AZCopyAdditions = [int] $AZCopySyncAdditionsRegex.Match($line).Value
                $AZCopyDeletions = [int] $AZCopySyncDeletionsRegex.Match($line).Value

                if ($AZCopyAdditions -ne 0) {
                    $ModsUpdated = $AZCopyAdditions
                }

                if ($AZCopyDeletions -ne 0) {
                    $DeletedMods = $AZCopyDeletions
                }

                if ($AZCopySyncErrorRegex.Match($line).Value) {
                    Write-ToLog "AZCopy Sync Error! $line"
                }
            }
        }
        else {
            Write-ToLog "Error 'azcopy.exe' or SAS Token not found!"
        }

        return $ModsUpdated, $DeletedMods
    }
    # === Handle UNC or local paths ===
    else {
        # --- Handle bins subfolder ---
        $ExternalBins = "$ModsPath\bins"
        if (Test-Path -Path $ExternalBins"\*.exe") {
            $ExternalBinsNames = Get-ChildItem -Path $ExternalBins -Name -Recurse -Include *.exe

            # Delete local bins that don't exist externally
            foreach ($Bin in $InternalBinsNames) {
                If ($Bin -notin $ExternalBinsNames ) {
                    Remove-Item $LocalMods\bins\$Bin -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }

            # Copy newer external bins
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

        # --- Handle mod files ---
        if ((Test-Path -Path $ExternalMods"\*.ps1") -or (Test-Path -Path $ExternalMods"\*.txt")) {
            $ExternalModsNames = Get-ChildItem -Path $ExternalMods -Name -Recurse -Include *.ps1, *.txt

            # Delete local mods that don't exist externally
            $DeletedMods = 0
            foreach ($Mod in $InternalModsNames) {
                If ($Mod -notin $ExternalModsNames ) {
                    Remove-Item $LocalMods\$Mod -Force -ErrorAction SilentlyContinue | Out-Null
                    $DeletedMods++
                }
            }

            # Copy newer external mods
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
