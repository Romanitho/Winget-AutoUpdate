#Function to check Black/White List Path

function Test-ListPath ($ListPath, $UseWhiteList) {
    # UNC, Web or Local Path
    if ($UseWhiteList){
        $ListType="included"
    }
    else {
        $ListType="excluded"
    }
    $LocalList = -join($WingetUpdatePath, "\", $ListType, "_apps.txt")
    $PathInfo=[System.Uri]$ListPath

    if($PathInfo.IsUnc){
        $PathType="UNC Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $dateExternal = (Get-Item "$ListPath").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
            }
        }
        else {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    elseif ($ListPath -like "http*"){
        $PathType="Web Path"
        $ExternalList = -join($ListPath, "/", $ListType, "_apps.txt")
        $wc = New-Object System.Net.WebClient
        try {
            $wc.OpenRead("$ExternalList").Close() | Out-Null
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $dateExternal = ([DateTime]$wc.ResponseHeaders['Last-Modified']).ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
            }
        }
        catch {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
    else {
        $PathType="Local Path"
        $ExternalList = -join($ListPath, "\", $ListType, "_apps.txt")
        if(Test-Path -Path $ExternalList -PathType leaf){
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is available..."
            $dateLocal = (Get-Item "$LocalList").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $dateExternal = (Get-Item "$ListPath").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            if ($dateExternal -gt $dateLocal) {
                Write-Host("$ExternalList is newer than $LocalList")
            }
        }
        else {
            Write-Output "Given path $ListPath type is $PathType and $ExternalList is not available..."
        }
    }
}

$WingetUpdatePath = "$env:ProgramData\Winget-AutoUpdate"
$ListPath = "https://www.knifmelti.se"
#$UseWhiteList = $true
#White List or Black List in share/online if differs
if ($WingetUpdatePath -ne $ListPath){
    Test-ListPath $ListPath $UseWhiteList
}
