#Function to check Black/White List External Path

function Test-ListPath ($ListPath, $UseWhiteList) {
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
    $PathInfo=[System.Uri]$ListPath

    if($PathInfo.IsUnc){
        $PathType="UNC Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateExternal = (Get-Item "$ExternalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
                return $true
            }
        }
        else {
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    elseif ($ListPath -like "http*"){
        $PathType="Web Path"
        $ExternalList = -join($ListPath, "/", $ListType, "_apps.txt")
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ExternalList").Close() | Out-Null
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
                return $true
            }
        }
        catch {
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    else {
        $PathType="Local Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateExternal = (Get-Item "$ExternalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
                return $true
            }
        }
        else {
            Write-Host "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    return $false
}

$WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
$ListPath = "https://www.knifmelti.se"
#$ListPath = "D:\Temp"
#$ListPath = "\\TempSERVER"

#$UseWhiteList = $true
#White List or Black List in share/online if differs
if ($WingetUpdatePath -ne $ListPath){
    $NoClean = Test-ListPath $ListPath $UseWhiteList
}

Write-Host $NoClean
