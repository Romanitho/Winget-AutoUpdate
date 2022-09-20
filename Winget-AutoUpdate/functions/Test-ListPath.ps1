#Function to check Black/White List External Path

function Test-ListPath ($ListPath, $UseWhiteList, $WingetUpdatePath) {
    # UNC, Web or Local Path
    if ($UseWhiteList){
        $ListType="included"
    }
    else {
        $ListType="excluded"
    }
    $LocalList = -join($WingetUpdatePath, "\", $ListType, "_apps.txt")
    if (Test-Path "$LocalList") {
        $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }
    $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
    $PathInfo=[System.Uri]$ListPath

    if($PathInfo.IsUnc){
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
    elseif ($ListPath -like "http*"){
        $ExternalList = -join($ListPath, "/", $ListType, "_apps.txt")
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

# $WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
# $ListPath = "https://www.knifmelti.se"
# #$ListPath = "D:\Temp"
# #$ListPath = "\\TempSERVER"
# #$UseWhiteList = $true

# #White List or Black List in share/online if differs
# if ($WingetUpdatePath -ne $ListPath){
#     $NoClean = Test-ListPath $ListPath $UseWhiteList $WingetUpdatePath
# }

# Write-Host $NoClean
