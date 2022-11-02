#Function to check Mods External Path

function Test-ModsPath ($ModsPath, $WingetUpdatePath) {
    # URL, UNC or Local Path
    # Get local and external Mods paths
    $LocalMods = -join ($WingetUpdatePath, "\", "mods")
    $ExternalMods = "$ModsPath\"

    # Check if mods exists
    if (Test-Path "$LocalMods\*.ps1") {
        $dateLocal = (Get-Item "$LocalMods").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }

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
        if (Test-Path -Path $ExternalMods -PathType leaf) {
            $dateExternal = (Get-Item "$ExternalMods").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                try {
                    Copy-Item $ExternalMods -Destination $LocalMods -Force
                }
                catch {
                    return $False
                }
                return $true
            }
        }
    }
    return $false
}
