#Function to check Black/White List External Path

function Test-ListPath ($ListPath, $UseWhiteList, $WingetUpdatePath) {
    # URL, UNC or Local Path
    if ($UseWhiteList){
        $ListType="included_apps.txt"
    }
    else {
        $ListType="excluded_apps.txt"
    }

    # Get local and external list paths
    $LocalList = -join($WingetUpdatePath, "\", $ListType)
    $ExternalList = -join($ListPath, "\", $ListType)

    # Check if a list exists
    if (Test-Path "$LocalList") {
        $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }

    # If path is URL
    if ($ListPath -like "http*"){
        $ExternalList = -join($ListPath, "/", $ListType)
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ExternalList").Close() | Out-Null
            $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                try {
                    $wc.DownloadFile($ExternalList, $LocalList)
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
        if(Test-Path -Path $ExternalList -PathType leaf){
            $dateExternal = (Get-Item "$ExternalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                try {
                    Copy-Item $ExternalList -Destination $LocalList -Force
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
